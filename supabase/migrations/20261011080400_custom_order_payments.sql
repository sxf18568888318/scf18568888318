begin;

alter table public.payments
 add column if not exists quote_id uuid references public.quotes(id),
 add column if not exists order_id uuid references public.factory_orders(id),
 add column if not exists reverses_payment_id uuid references public.payments(id),
 add column if not exists request_id uuid,
 add column if not exists created_at timestamptz not null default now();
create unique index if not exists custom_payment_request_unique_idx on public.payments(request_id) where request_id is not null;
create unique index if not exists custom_payment_single_reversal_idx on public.payments(reverses_payment_id) where reverses_payment_id is not null;
alter table public.payments drop constraint if exists custom_payment_nonzero_amount_check;
alter table public.payments add constraint custom_payment_nonzero_amount_check check(amount<>0);

alter table public.payment_plans
 add column if not exists quote_id uuid references public.quotes(id),
 add column if not exists order_id uuid references public.factory_orders(id),
 add column if not exists created_by uuid references auth.users(id),
 add column if not exists request_id uuid;
create unique index if not exists custom_payment_plan_request_unique_idx on public.payment_plans(request_id) where request_id is not null;
alter table public.payment_plans drop constraint if exists custom_payment_plan_milestone_check;
alter table public.payment_plans add constraint custom_payment_plan_milestone_check check(name in ('定金','中期','尾款') or quote_id is null and order_id is null);

-- Keep legacy unlinked payment entry available, but custom-linked writes flow only
-- through the validated RPCs. Payment rows are append-only for all API callers.
revoke update,delete on public.payments from authenticated;
drop policy if exists payments_access on public.payments;
create policy payments_access on public.payments for select to authenticated
 using(app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())));
create policy payments_legacy_insert on public.payments for insert to authenticated
 with check(quote_id is null and order_id is null and (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()))));
drop policy if exists payment_plans_access on public.payment_plans;
create policy payment_plans_access on public.payment_plans for select to authenticated
 using(app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())));
create policy payment_plans_legacy_insert on public.payment_plans for insert to authenticated
 with check(quote_id is null and order_id is null and (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()))));
create policy payment_plans_legacy_update on public.payment_plans for update to authenticated
 using(quote_id is null and order_id is null and (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()))))
 with check(quote_id is null and order_id is null and (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()))));

grant select,insert on public.payments to anju_custom_executor;
grant update on public.payments to anju_custom_executor;
grant select,insert,update on public.payment_plans to anju_custom_executor;
drop policy if exists custom_executor_payment_access on public.payments;
create policy custom_executor_payment_access on public.payments for all to anju_custom_executor
 using(custom_private.customer_allowed(customer_id))
 with check(custom_private.customer_allowed(customer_id));
drop policy if exists custom_executor_payment_plan_access on public.payment_plans;
create policy custom_executor_payment_plan_access on public.payment_plans for all to anju_custom_executor
 using(custom_private.customer_allowed(customer_id))
 with check(custom_private.customer_allowed(customer_id));
drop policy if exists custom_finance_receipt_owner_access on custom_private.finance_mutation_receipts;
create policy custom_finance_receipt_owner_access on custom_private.finance_mutation_receipts
 for all to anju_custom_executor
 using(actor_id=custom_private.request_uid() and custom_private.request_role() in ('owner','designer'))
 with check(actor_id=custom_private.request_uid() and custom_private.request_role() in ('owner','designer'));

create or replace function custom_private.validate_custom_payment_links(p_customer_id uuid,p_quote_id uuid,p_order_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select custom_private.customer_allowed(p_customer_id)
 and (p_quote_id is null or exists(select 1 from public.quotes q where q.id=p_quote_id and q.customer_id=p_customer_id and q.business_line='custom'))
 and (p_order_id is null or exists(select 1 from public.factory_orders o where o.id=p_order_id and o.customer_id=p_customer_id and o.custom_quote_id is not null))
 and (p_quote_id is null or p_order_id is null or exists(select 1 from public.factory_orders o where o.id=p_order_id and o.custom_quote_id=p_quote_id));
$$;
alter function custom_private.validate_custom_payment_links(uuid,uuid,uuid) owner to anju_custom_executor;
revoke all on function custom_private.validate_custom_payment_links(uuid,uuid,uuid) from public,anon;
grant execute on function custom_private.validate_custom_payment_links(uuid,uuid,uuid) to anju_custom_executor;

create or replace function api.custom_save_payment_plan(
 p_customer_id uuid,p_quote_id uuid,p_order_id uuid,p_name text,p_amount numeric,p_planned_date date,p_sort_order integer,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid;v_id uuid;v_receipt custom_private.finance_mutation_receipts%rowtype;
begin
 perform custom_private.require_roles(array['owner','designer']);v_actor:=custom_private.request_uid();
 if p_request_id is null or p_name not in ('定金','中期','尾款') or p_amount is null or p_amount<0 then raise exception using errcode='22023',message='invalid_payment_plan';end if;
 select * into v_receipt from custom_private.finance_mutation_receipts where request_id=p_request_id;
 if found then
  if v_receipt.actor_id<>v_actor or v_receipt.operation<>'payment_plan_create' then raise exception using errcode='23505',message='request_id_conflict';end if;
  return jsonb_build_object('status','existing','id',v_receipt.replacement_id);
 end if;
 if not custom_private.validate_custom_payment_links(p_customer_id,p_quote_id,p_order_id) then raise exception using errcode='42501',message='custom_customer_forbidden';end if;
 insert into public.payment_plans(customer_id,quote_id,order_id,name,planned_amount,planned_date,sort_order,created_by,request_id)
 values(p_customer_id,p_quote_id,p_order_id,p_name,p_amount,p_planned_date,coalesce(p_sort_order,0),v_actor,p_request_id) returning id into v_id;
 insert into custom_private.finance_mutation_receipts(request_id,actor_id,operation,replacement_id)
 values(p_request_id,v_actor,'payment_plan_create',v_id);
 return jsonb_build_object('status','created','id',v_id);
end $$;
alter function api.custom_save_payment_plan(uuid,uuid,uuid,text,numeric,date,integer,uuid) owner to anju_custom_executor;
revoke all on function api.custom_save_payment_plan(uuid,uuid,uuid,text,numeric,date,integer,uuid) from public,anon;
grant execute on function api.custom_save_payment_plan(uuid,uuid,uuid,text,numeric,date,integer,uuid) to authenticated;

create or replace function api.custom_record_payment(
 p_customer_id uuid,p_quote_id uuid,p_order_id uuid,p_amount numeric,p_paid_at date,p_method text,p_note text,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid;v_id uuid;v_receipt custom_private.finance_mutation_receipts%rowtype;
begin
 perform custom_private.require_roles(array['owner','designer']);v_actor:=custom_private.request_uid();
 if p_request_id is null or p_amount is null or p_amount=0 then raise exception using errcode='22023',message='invalid_payment';end if;
 select * into v_receipt from custom_private.finance_mutation_receipts where request_id=p_request_id;
 if found then
  if v_receipt.actor_id<>v_actor or v_receipt.operation<>'payment_create' then raise exception using errcode='23505',message='request_id_conflict';end if;
  return jsonb_build_object('status','existing','id',v_receipt.replacement_id);
 end if;
 if not custom_private.validate_custom_payment_links(p_customer_id,p_quote_id,p_order_id) then raise exception using errcode='42501',message='custom_customer_forbidden';end if;
 insert into public.payments(customer_id,quote_id,order_id,amount,paid_at,method,note,created_by,request_id)
 values(p_customer_id,p_quote_id,p_order_id,p_amount,coalesce(p_paid_at,current_date),coalesce(nullif(p_method,''),'其他'),coalesce(p_note,''),v_actor,p_request_id) returning id into v_id;
 insert into custom_private.finance_mutation_receipts(request_id,actor_id,operation,replacement_id)
 values(p_request_id,v_actor,'payment_create',v_id);
 return jsonb_build_object('status','created','id',v_id);
end $$;
alter function api.custom_record_payment(uuid,uuid,uuid,numeric,date,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.custom_record_payment(uuid,uuid,uuid,numeric,date,text,text,uuid) from public,anon;
grant execute on function api.custom_record_payment(uuid,uuid,uuid,numeric,date,text,text,uuid) to authenticated;

create or replace function api.custom_correct_payment(
 p_payment_id uuid,p_new_amount numeric,p_note text,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old public.payments%rowtype;v_actor uuid;v_reversal uuid;v_replacement uuid;v_receipt custom_private.finance_mutation_receipts%rowtype;
begin
 perform custom_private.require_roles(array['owner','designer']);v_actor:=custom_private.request_uid();
 if p_request_id is null or p_new_amount is null or p_new_amount=0 then raise exception using errcode='22023',message='invalid_payment';end if;
 select * into v_receipt from custom_private.finance_mutation_receipts where request_id=p_request_id;
 if found then
  if v_receipt.actor_id<>v_actor or v_receipt.operation<>'payment_correct' or v_receipt.original_id<>p_payment_id then raise exception using errcode='23505',message='request_id_conflict';end if;
  return jsonb_build_object('status','existing','reversal_id',v_receipt.reversal_id,'replacement_id',v_receipt.replacement_id);
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_payment_id::text,0));
 select * into v_old from public.payments where id=p_payment_id for update;
 if v_old.id is null or not custom_private.customer_allowed(v_old.customer_id) then raise exception using errcode='42501',message='payment_forbidden';end if;
 if v_old.reverses_payment_id is not null or exists(select 1 from public.payments p where p.reverses_payment_id=p_payment_id) then raise exception using errcode='23514',message='payment_already_corrected';end if;
 insert into public.payments(customer_id,quote_id,order_id,amount,paid_at,method,note,created_by,reverses_payment_id)
 values(v_old.customer_id,v_old.quote_id,v_old.order_id,-v_old.amount,current_date,'冲正','红冲：'||coalesce(p_note,''),v_actor,p_payment_id) returning id into v_reversal;
 insert into public.payments(customer_id,quote_id,order_id,amount,paid_at,method,note,created_by,request_id)
 values(v_old.customer_id,v_old.quote_id,v_old.order_id,p_new_amount,current_date,v_old.method,coalesce(p_note,''),v_actor,p_request_id) returning id into v_replacement;
 insert into custom_private.finance_mutation_receipts(request_id,actor_id,operation,original_id,reversal_id,replacement_id)
 values(p_request_id,v_actor,'payment_correct',p_payment_id,v_reversal,v_replacement);
 return jsonb_build_object('status','corrected','reversal_id',v_reversal,'replacement_id',v_replacement);
end $$;
alter function api.custom_correct_payment(uuid,numeric,text,uuid) owner to anju_custom_executor;
revoke all on function api.custom_correct_payment(uuid,numeric,text,uuid) from public,anon;
grant execute on function api.custom_correct_payment(uuid,numeric,text,uuid) to authenticated;

create or replace function custom_private.read_custom_order_receivables_step7(p_owner_only boolean)
returns table(factory_order_id uuid,customer_id uuid,customer_name text,quote_id uuid,order_status text,order_amount numeric,received_amount numeric,receivable_amount numeric,completed_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if p_owner_only then perform custom_private.require_roles(array['owner']);else perform custom_private.require_roles(array['owner','designer']);end if;
 return query select o.id,o.customer_id,c.name,o.custom_quote_id,o.status,o.order_amount,
   coalesce(sum(pay.amount),0)::numeric, o.order_amount-coalesce(sum(pay.amount),0)::numeric,o.completed_at
 from public.factory_orders o join public.customers c on c.id=o.customer_id
 left join public.payments pay on pay.order_id=o.id or (pay.order_id is null and pay.quote_id=o.custom_quote_id)
 where o.custom_quote_id is not null and custom_private.customer_allowed(o.customer_id)
 group by o.id,c.name order by o.created_at desc;
end $$;
alter function custom_private.read_custom_order_receivables_step7(boolean) owner to anju_custom_executor;
revoke all on function custom_private.read_custom_order_receivables_step7(boolean) from public,anon;
grant execute on function custom_private.read_custom_order_receivables_step7(boolean) to anju_custom_executor,authenticated;
create or replace view api.owner_custom_order_receivables with(security_invoker=false) as
 select * from custom_private.read_custom_order_receivables_step7(true);
alter view api.owner_custom_order_receivables owner to anju_custom_executor;
revoke all on api.owner_custom_order_receivables from public,anon;
grant select on api.owner_custom_order_receivables to authenticated;
create or replace view api.my_custom_order_receivables with(security_invoker=false) as
 select * from custom_private.read_custom_order_receivables_step7(false);
alter view api.my_custom_order_receivables owner to anju_custom_executor;
revoke all on api.my_custom_order_receivables from public,anon;
grant select on api.my_custom_order_receivables to authenticated;

notify pgrst,'reload schema';
commit;
