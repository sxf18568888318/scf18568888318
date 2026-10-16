begin;

-- Append-only ledger correction metadata. Source issue/return rows stay immutable.
alter table public.custom_cost_entries
  add column if not exists reverses_entry_id uuid references public.custom_cost_entries(id);
create unique index if not exists custom_cost_single_reversal_idx
  on public.custom_cost_entries(reverses_entry_id) where reverses_entry_id is not null;

alter table public.fixed_costs
  add column if not exists item text not null default '',
  add column if not exists ownership text not null default '',
  add column if not exists reverses_id uuid references public.fixed_costs(id),
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists request_id uuid;
create unique index if not exists fixed_cost_single_reversal_idx
  on public.fixed_costs(reverses_id) where reverses_id is not null;
create unique index if not exists fixed_cost_request_unique_idx
  on public.fixed_costs(request_id) where request_id is not null;

create table if not exists custom_private.finance_mutation_receipts(
 request_id uuid primary key, actor_id uuid not null, operation text not null,
 original_id uuid, reversal_id uuid, replacement_id uuid, created_at timestamptz not null default now()
);
alter table custom_private.finance_mutation_receipts enable row level security;
alter table custom_private.finance_mutation_receipts force row level security;
revoke all on custom_private.finance_mutation_receipts from public,anon,authenticated;
grant select,insert on custom_private.finance_mutation_receipts to anju_custom_executor;
drop policy if exists custom_finance_receipt_owner_access on custom_private.finance_mutation_receipts;
create policy custom_finance_receipt_owner_access on custom_private.finance_mutation_receipts
 for all to anju_custom_executor
 using (actor_id=custom_private.request_uid() and custom_private.request_role()='owner')
 with check (actor_id=custom_private.request_uid() and custom_private.request_role()='owner');

grant select,insert,update on public.fixed_costs to anju_custom_executor;
drop policy if exists custom_step7_finance_owner_fixed_costs on public.fixed_costs;
create policy custom_step7_finance_owner_fixed_costs on public.fixed_costs
 for select to anju_custom_executor using (app.role()='owner');
drop policy if exists custom_step7_finance_write_fixed_costs on public.fixed_costs;
create policy custom_step7_finance_write_fixed_costs on public.fixed_costs
 for all to anju_custom_executor using (app.role()='owner') with check (app.role()='owner');

create or replace function api.custom_owner_record_order_cost(
 p_order_id uuid,p_category text,p_amount numeric,p_note text,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_actor uuid; v_receipt custom_private.finance_mutation_receipts%rowtype;
begin
 perform custom_private.require_roles(array['owner']); v_actor:=custom_private.request_uid();
 if p_request_id is null or p_amount is null or p_amount<=0 or p_category not in ('人工','安装','外协','其他') then
   raise exception using errcode='22023',message='invalid_order_cost';
 end if;
 select * into v_receipt from custom_private.finance_mutation_receipts where request_id=p_request_id;
 if found then
   if v_receipt.actor_id<>v_actor or v_receipt.operation<>'order_cost_create' then raise exception using errcode='23505',message='request_id_conflict'; end if;
   return jsonb_build_object('status','existing','id',v_receipt.replacement_id);
 end if;
 if not exists(select 1 from public.factory_orders o where o.id=p_order_id and o.custom_quote_id is not null) then
   raise exception using errcode='42501',message='custom_order_forbidden';
 end if;
 insert into public.custom_cost_entries(factory_order_id,category,occurred_at,quantity,unit,unit_cost,amount,note,created_by,request_id)
 values(p_order_id,p_category,current_date,1,'笔',p_amount,p_amount,coalesce(p_note,''),v_actor,p_request_id) returning id into v_id;
 insert into custom_private.finance_mutation_receipts(request_id,actor_id,operation,replacement_id)
 values(p_request_id,v_actor,'order_cost_create',v_id);
 return jsonb_build_object('status','created','id',v_id);
end $$;
alter function api.custom_owner_record_order_cost(uuid,text,numeric,text,uuid) owner to anju_custom_executor;
revoke all on function api.custom_owner_record_order_cost(uuid,text,numeric,text,uuid) from public,anon;
grant execute on function api.custom_owner_record_order_cost(uuid,text,numeric,text,uuid) to authenticated;

create or replace function api.custom_owner_correct_order_cost(
 p_entry_id uuid,p_new_category text,p_new_amount numeric,p_note text,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old_id uuid; v_order_id uuid; v_old_category text; v_old_amount numeric; v_source uuid; v_reverse uuid;
 v_actor uuid; v_reversal uuid; v_replacement uuid; v_receipt custom_private.finance_mutation_receipts%rowtype;
begin
 perform custom_private.require_roles(array['owner']); v_actor:=custom_private.request_uid();
 if p_request_id is null or p_new_amount is null or p_new_amount<=0 or p_new_category not in ('人工','安装','外协','其他') then
   raise exception using errcode='22023',message='invalid_order_cost';
 end if;
 select * into v_receipt from custom_private.finance_mutation_receipts where request_id=p_request_id;
 if found then
   if v_receipt.actor_id<>v_actor or v_receipt.operation<>'order_cost_correct' or v_receipt.original_id<>p_entry_id then raise exception using errcode='23505',message='request_id_conflict'; end if;
   return jsonb_build_object('status','existing','reversal_id',v_receipt.reversal_id,'replacement_id',v_receipt.replacement_id);
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_entry_id::text,0));
 select c.id,c.factory_order_id,c.category,c.amount,c.source_transaction_id,c.reverses_entry_id
 into v_old_id,v_order_id,v_old_category,v_old_amount,v_source,v_reverse
 from public.custom_cost_entries c where c.id=p_entry_id;
 if v_old_id is null then raise exception using errcode='42501',message='cost_entry_not_found'; end if;
 if v_source is not null or v_reverse is not null then raise exception using errcode='42501',message='cost_entry_not_correctable'; end if;
 if exists(select 1 from public.custom_cost_entries c where c.reverses_entry_id=p_entry_id) then raise exception using errcode='23514',message='cost_entry_already_corrected'; end if;
 insert into public.custom_cost_entries(factory_order_id,category,occurred_at,quantity,unit,unit_cost,amount,note,created_by,reverses_entry_id)
 values(v_order_id,v_old_category,current_date,1,'笔',-v_old_amount,-v_old_amount,'红冲：'||coalesce(p_note,''),v_actor,p_entry_id) returning id into v_reversal;
 insert into public.custom_cost_entries(factory_order_id,category,occurred_at,quantity,unit,unit_cost,amount,note,created_by,request_id)
 values(v_order_id,p_new_category,current_date,1,'笔',p_new_amount,p_new_amount,coalesce(p_note,''),v_actor,p_request_id) returning id into v_replacement;
 insert into custom_private.finance_mutation_receipts(request_id,actor_id,operation,original_id,reversal_id,replacement_id)
 values(p_request_id,v_actor,'order_cost_correct',p_entry_id,v_reversal,v_replacement);
 return jsonb_build_object('status','corrected','reversal_id',v_reversal,'replacement_id',v_replacement);
end $$;
alter function api.custom_owner_correct_order_cost(uuid,text,numeric,text,uuid) owner to anju_custom_executor;
revoke all on function api.custom_owner_correct_order_cost(uuid,text,numeric,text,uuid) from public,anon;
grant execute on function api.custom_owner_correct_order_cost(uuid,text,numeric,text,uuid) to authenticated;

create or replace function api.custom_owner_save_fixed_cost(
 p_id uuid,p_cost_month date,p_category text,p_amount numeric,p_item text,p_ownership text,p_note text,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid; v_id uuid; v_reversal uuid; v_receipt custom_private.finance_mutation_receipts%rowtype; v_old public.fixed_costs%rowtype;
begin
 perform custom_private.require_roles(array['owner']); v_actor:=custom_private.request_uid();
 if p_request_id is null or p_cost_month is null or p_amount is null or p_amount<=0 or p_category not in ('房租','水电','固定人工','折旧','办公软件','营销推广','其他') then
   raise exception using errcode='22023',message='invalid_fixed_cost';
 end if;
 select * into v_receipt from custom_private.finance_mutation_receipts where request_id=p_request_id;
 if found then
   if v_receipt.actor_id<>v_actor or v_receipt.operation<>'fixed_cost_save' or v_receipt.original_id is distinct from p_id then raise exception using errcode='23505',message='request_id_conflict'; end if;
   return jsonb_build_object('status','existing','id',v_receipt.replacement_id,'reversal_id',v_receipt.reversal_id);
 end if;
 if p_id is not null then
   select * into v_old from public.fixed_costs where id=p_id for update;
   if not found or v_old.reverses_id is not null or exists(select 1 from public.fixed_costs f where f.reverses_id=p_id) then
     raise exception using errcode='23514',message='fixed_cost_not_correctable';
   end if;
   insert into public.fixed_costs(cost_month,category,amount,note,item,ownership,reverses_id,created_by)
   values(v_old.cost_month,v_old.category,-v_old.amount,'红冲：'||coalesce(p_note,''),v_old.item,v_old.ownership,p_id,v_actor) returning id into v_reversal;
 end if;
 insert into public.fixed_costs(cost_month,category,amount,note,item,ownership,created_by,request_id)
 values(date_trunc('month',p_cost_month)::date,p_category,p_amount,coalesce(p_note,''),coalesce(p_item,''),coalesce(p_ownership,''),v_actor,p_request_id)
 returning id into v_id;
 insert into custom_private.finance_mutation_receipts(request_id,actor_id,operation,original_id,reversal_id,replacement_id)
 values(p_request_id,v_actor,'fixed_cost_save',p_id,v_reversal,v_id);
 return jsonb_build_object('status',case when p_id is null then 'created' else 'corrected' end,'id',v_id,'reversal_id',v_reversal);
end $$;
alter function api.custom_owner_save_fixed_cost(uuid,date,text,numeric,text,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.custom_owner_save_fixed_cost(uuid,date,text,numeric,text,text,text,uuid) from public,anon;
grant execute on function api.custom_owner_save_fixed_cost(uuid,date,text,numeric,text,text,text,uuid) to authenticated;

create or replace function custom_private.read_owner_fixed_cost_ledger_step7()
returns table(id uuid,cost_month date,category text,amount numeric,item text,ownership text,note text,reverses_id uuid,created_by uuid,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query select f.id,f.cost_month,f.category,f.amount,f.item,f.ownership,f.note,f.reverses_id,f.created_by,f.created_at
 from public.fixed_costs f order by f.cost_month desc,f.created_at desc;
end $$;
alter function custom_private.read_owner_fixed_cost_ledger_step7() owner to anju_custom_executor;
revoke all on function custom_private.read_owner_fixed_cost_ledger_step7() from public,anon;
grant execute on function custom_private.read_owner_fixed_cost_ledger_step7() to anju_custom_executor,authenticated;
create or replace view api.owner_fixed_cost_ledger with(security_invoker=false) as
 select * from custom_private.read_owner_fixed_cost_ledger_step7();
alter view api.owner_fixed_cost_ledger owner to anju_custom_executor;
revoke all on api.owner_fixed_cost_ledger from public,anon;
grant select on api.owner_fixed_cost_ledger to authenticated;

notify pgrst,'reload schema';
commit;
