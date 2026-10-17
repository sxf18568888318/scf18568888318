begin;

create table if not exists factory_private.order_cash_entry_documents (
  id uuid primary key default gen_random_uuid(),
  cash_entry_id uuid not null references factory_private.order_cash_entries(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null,
  file_size bigint not null check (file_size > 0 and file_size <= 20971520),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  request_id uuid not null,
  constraint order_cash_entry_documents_path_check check (storage_path !~ '(^/|\.\.|//)')
);
alter table factory_private.order_cash_entry_documents owner to postgres;
revoke all on factory_private.order_cash_entry_documents from public, anon, authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('factory-payment-proofs','factory-payment-proofs',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function factory_private.cash_proof_upload_allowed(p_name text)
returns boolean language plpgsql stable security definer set search_path=''
as $$
declare v_order_id uuid;
begin
  if custom_private.request_role() not in ('owner','factory_manager')
     or p_name is null or p_name !~ '^cash/[0-9a-fA-F-]{36}/[^/]+$' or p_name like '%..%' then return false; end if;
  begin v_order_id:=split_part(p_name,'/',2)::uuid; exception when others then return false; end;
  return factory_private.order_scope_allowed(v_order_id,'write');
end $$;
alter function factory_private.cash_proof_upload_allowed(text) owner to postgres;
revoke all on function factory_private.cash_proof_upload_allowed(text) from public,anon;
grant execute on function factory_private.cash_proof_upload_allowed(text) to authenticated;

create or replace function factory_private.cash_proof_read_allowed(p_name text)
returns boolean language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' or p_name is null then return false; end if;
  return exists(select 1 from factory_private.order_cash_entry_documents d
    where d.storage_path=p_name);
end $$;
alter function factory_private.cash_proof_read_allowed(text) owner to postgres;
revoke all on function factory_private.cash_proof_read_allowed(text) from public,anon;
grant execute on function factory_private.cash_proof_read_allowed(text) to authenticated;

create or replace function factory_private.cash_proof_is_linked(p_name text)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from factory_private.order_cash_entry_documents d where d.storage_path=p_name) $$;
alter function factory_private.cash_proof_is_linked(text) owner to postgres;
revoke all on function factory_private.cash_proof_is_linked(text) from public,anon;
grant execute on function factory_private.cash_proof_is_linked(text) to authenticated;

drop policy if exists factory_payment_proofs_insert on storage.objects;
create policy factory_payment_proofs_insert on storage.objects for insert to authenticated
  with check (bucket_id='factory-payment-proofs' and factory_private.cash_proof_upload_allowed(name));
drop policy if exists factory_payment_proofs_read on storage.objects;
create policy factory_payment_proofs_read on storage.objects for select to authenticated
  using (bucket_id='factory-payment-proofs' and factory_private.cash_proof_read_allowed(name));
drop policy if exists factory_payment_proofs_delete on storage.objects;
create policy factory_payment_proofs_delete on storage.objects for delete to authenticated
  using (bucket_id='factory-payment-proofs' and not factory_private.cash_proof_is_linked(name) and (
    custom_private.request_role()='owner'
    or (custom_private.request_role()='factory_manager' and factory_private.cash_proof_upload_allowed(name))
  ));

-- These functions are invoked by database triggers, never by application RPC.
revoke all on function public.handle_new_user_role() from public,anon,authenticated;
revoke all on function public.rls_auto_enable() from public,anon,authenticated;

create or replace function api.factory_record_cash_entry_with_proofs(
  p_order_id uuid,p_kind text,p_date date,p_amount numeric,p_method text,p_counterparty text,
  p_note text,p_stage text,p_sequence integer,p_documents jsonb,p_request_id uuid
)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_entry_id uuid; v_doc jsonb; v_path text; v_name text; v_mime text; v_size bigint;
begin
  if custom_private.request_role() not in ('owner','factory_manager')
     or not factory_private.order_scope_allowed(p_order_id,'write') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  if p_kind not in ('收款','付款') or p_amount is null or p_amount<=0 or p_request_id is null
     or (p_kind='收款' and (p_stage not in ('定金','中期款','尾款','其他') or p_sequence is null or p_sequence<=0))
     or p_documents is null or jsonb_typeof(p_documents)<>'array' or jsonb_array_length(p_documents)>8 then
    raise exception using errcode='22023',message='factory_cash_invalid';
  end if;
  for v_doc in select value from jsonb_array_elements(p_documents) loop
    v_path:=v_doc->>'storage_path'; v_name:=v_doc->>'file_name'; v_mime:=v_doc->>'mime_type';
    begin v_size:=(v_doc->>'file_size')::bigint; exception when others then v_size:=0; end;
    if v_path is null or v_path not like 'cash/'||p_order_id::text||'/%'
       or not factory_private.cash_proof_upload_allowed(v_path)
       or v_mime not in ('image/jpeg','image/png','image/webp','application/pdf')
       or v_size<=0 or v_size>20971520 or coalesce(length(v_name),0)=0 or length(v_name)>255 then
      raise exception using errcode='22023',message='factory_cash_proof_invalid';
    end if;
  end loop;
  v_dup:=factory_private.claim_request('factory_record_cash_entry_with_proofs',p_request_id,
    jsonb_build_object('order_id',p_order_id,'kind',p_kind,'date',p_date,'amount',p_amount,
      'method',p_method,'counterparty',p_counterparty,'note',p_note,'stage',p_stage,'sequence',p_sequence,'documents',p_documents));
  if not v_dup then
    insert into factory_private.order_cash_entries(order_id,entry_kind,entry_date,amount,method,counterparty,note,
      payment_stage,receipt_sequence,created_by,request_id)
    values(p_order_id,p_kind,coalesce(p_date,current_date),p_amount,left(coalesce(p_method,''),60),
      left(coalesce(p_counterparty,''),160),left(coalesce(p_note,''),1000),
      case when p_kind='收款' then p_stage else '' end,
      case when p_kind='收款' then p_sequence else null end,custom_private.request_uid(),p_request_id)
    returning id into v_entry_id;
    for v_doc in select value from jsonb_array_elements(p_documents) loop
      insert into factory_private.order_cash_entry_documents(cash_entry_id,storage_path,file_name,mime_type,file_size,created_by,request_id)
      values(v_entry_id,v_doc->>'storage_path',left(v_doc->>'file_name',255),v_doc->>'mime_type',
        (v_doc->>'file_size')::bigint,custom_private.request_uid(),p_request_id);
    end loop;
  else
    select id into v_entry_id from factory_private.order_cash_entries where request_id=p_request_id;
  end if;
  return jsonb_build_object('status','ok','id',v_entry_id);
end
$$;
alter function api.factory_record_cash_entry_with_proofs(uuid,text,date,numeric,text,text,text,text,integer,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.factory_record_cash_entry_with_proofs(uuid,text,date,numeric,text,text,text,text,integer,jsonb,uuid) from public,anon;
grant execute on function api.factory_record_cash_entry_with_proofs(uuid,text,date,numeric,text,text,text,text,integer,jsonb,uuid) to authenticated;

create or replace function api.owner_factory_cash_ledger_v3()
returns table(id uuid,order_id uuid,entry_kind text,entry_date date,amount numeric,method text,counterparty text,note text,
  order_no text,customer_project text,payment_stage text,receipt_sequence integer,proof_documents jsonb)
language plpgsql stable security definer set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner']);
  return query
  select e.id,e.order_id,e.entry_kind,e.entry_date,e.amount,e.method,e.counterparty,e.note,
    w.order_no,w.customer_project,e.payment_stage,e.receipt_sequence,
    coalesce(jsonb_agg(jsonb_build_object('id',d.id,'path',d.storage_path,'name',d.file_name,'mime_type',d.mime_type,'file_size',d.file_size)
      order by d.created_at) filter(where d.id is not null),'[]'::jsonb)
  from factory_private.order_cash_entries e
  join factory_private.work_orders w on w.id=e.order_id
  left join factory_private.order_cash_entry_documents d on d.cash_entry_id=e.id
  group by e.id,w.order_no,w.customer_project
  order by e.entry_date desc,e.created_at desc;
end
$$;
alter function api.owner_factory_cash_ledger_v3() owner to anju_custom_executor;
revoke all on function api.owner_factory_cash_ledger_v3() from public,anon;
grant execute on function api.owner_factory_cash_ledger_v3() to authenticated;

create or replace function api.owner_factory_payroll_adjustment_targets(p_month date default null)
returns table(snapshot_id uuid,payroll_month date,employee_name text,amount numeric)
language plpgsql stable security definer set search_path=''
as $$ begin
  perform custom_private.require_roles(array['owner']);
  return query select s.id,s.payroll_month::date,s.employee_name_snapshot,
    (s.amount+coalesce(adj.adjustments,0))::numeric
  from factory_private.monthly_payroll_snapshots s
  left join lateral (select sum(x.amount) adjustments from factory_private.monthly_payroll_adjustments x where x.snapshot_id=s.id) adj on true
  where p_month is null or s.payroll_month=date_trunc('month',p_month)::date
  order by s.payroll_month desc,s.employee_name_snapshot;
end $$;
alter function api.owner_factory_payroll_adjustment_targets(date) owner to anju_custom_executor;
revoke all on function api.owner_factory_payroll_adjustment_targets(date) from public,anon;
grant execute on function api.owner_factory_payroll_adjustment_targets(date) to authenticated;
notify pgrst,'reload schema';
commit;
