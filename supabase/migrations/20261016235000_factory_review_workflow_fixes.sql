-- Factory-only review fixes: schedule fields, collection staging, owner public costs,
-- and atomic batch inventory receipt. Existing business rows are not rewritten.
begin;

alter table factory_private.work_orders
  add column if not exists planned_start_date date,
  add column if not exists schedule_note text not null default '';

alter table factory_private.order_cash_entries
  add column if not exists payment_stage text not null default '',
  add column if not exists receipt_sequence integer;
alter table factory_private.order_cash_entries
  drop constraint if exists order_cash_entries_payment_stage_check,
  drop constraint if exists order_cash_entries_receipt_sequence_check;
alter table factory_private.order_cash_entries
  add constraint order_cash_entries_payment_stage_check
    check (payment_stage in ('','定金','中期款','尾款','其他')),
  add constraint order_cash_entries_receipt_sequence_check
    check (receipt_sequence is null or receipt_sequence > 0);

create or replace function api.factory_update_order_schedule(
  p_order_id uuid,p_planned_start_date date,p_delivery_date date,p_note text,p_request_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean;
begin
  if custom_private.request_role() not in ('owner','factory_manager')
     or not factory_private.order_scope_allowed(p_order_id,'write') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  if p_request_id is null or p_planned_start_date is null or p_delivery_date is null
     or p_planned_start_date>p_delivery_date then
    raise exception using errcode='22023',message='factory_invalid_schedule';
  end if;
  v_dup:=factory_private.claim_request('factory_update_order_schedule',p_request_id,
    jsonb_build_object('order',p_order_id,'start',p_planned_start_date,'delivery',p_delivery_date,'note',p_note));
  if not v_dup then
    update factory_private.work_orders
       set planned_start_date=p_planned_start_date,delivery_date=p_delivery_date,
           schedule_note=left(coalesce(p_note,''),1000),updated_at=now()
     where id=p_order_id;
    if not found then raise exception using errcode='P0002',message='factory_order_not_found'; end if;
  end if;
  return jsonb_build_object('status','ok');
end
$$;
alter function api.factory_update_order_schedule(uuid,date,date,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_update_order_schedule(uuid,date,date,text,uuid) from public,anon;
grant execute on function api.factory_update_order_schedule(uuid,date,date,text,uuid) to authenticated;

create or replace function api.factory_record_cash_entry(
  p_order_id uuid,p_kind text,p_date date,p_amount numeric,p_method text,p_counterparty text,
  p_note text,p_stage text,p_sequence integer,p_request_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean;
begin
  if custom_private.request_role() not in ('owner','factory_manager')
     or not factory_private.order_scope_allowed(p_order_id,'write') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  if p_kind not in ('收款','付款') or p_amount is null or p_amount<=0 or p_request_id is null
     or (p_kind='收款' and (p_stage not in ('定金','中期款','尾款','其他') or p_sequence is null or p_sequence<=0)) then
    raise exception using errcode='22023',message='factory_cash_invalid';
  end if;
  v_dup:=factory_private.claim_request('factory_record_cash_entry',p_request_id,
    jsonb_build_object('order_id',p_order_id,'kind',p_kind,'date',p_date,'amount',p_amount,
      'method',p_method,'counterparty',p_counterparty,'note',p_note,'stage',p_stage,'sequence',p_sequence));
  if not v_dup then
    insert into factory_private.order_cash_entries(order_id,entry_kind,entry_date,amount,method,counterparty,
      note,payment_stage,receipt_sequence,created_by,request_id)
    values(p_order_id,p_kind,coalesce(p_date,current_date),p_amount,left(coalesce(p_method,''),60),
      left(coalesce(p_counterparty,''),160),left(coalesce(p_note,''),1000),
      case when p_kind='收款' then p_stage else '' end,
      case when p_kind='收款' then p_sequence else null end,custom_private.request_uid(),p_request_id);
  end if;
  return jsonb_build_object('status','ok');
end
$$;
alter function api.factory_record_cash_entry(uuid,text,date,numeric,text,text,text,text,integer,uuid) owner to anju_custom_executor;
revoke all on function api.factory_record_cash_entry(uuid,text,date,numeric,text,text,text,text,integer,uuid) from public,anon;
grant execute on function api.factory_record_cash_entry(uuid,text,date,numeric,text,text,text,text,integer,uuid) to authenticated;

create or replace function api.owner_factory_cash_ledger_v2()
returns table(id uuid,order_id uuid,entry_kind text,entry_date date,amount numeric,method text,
  counterparty text,note text,order_no text,customer_project text,payment_stage text,receipt_sequence integer)
language plpgsql stable security definer set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner']);
  return query select x.id,x.order_id,x.entry_kind,x.entry_date,x.amount,x.method,x.counterparty,x.note,
    w.order_no,w.customer_project,x.payment_stage,x.receipt_sequence
  from factory_private.order_cash_entries x
  join factory_private.work_orders w on w.id=x.order_id
  order by x.entry_date desc,x.created_at desc;
end
$$;
alter function api.owner_factory_cash_ledger_v2() owner to anju_custom_executor;
revoke all on function api.owner_factory_cash_ledger_v2() from public,anon;
grant execute on function api.owner_factory_cash_ledger_v2() to authenticated;

create or replace function api.factory_order_dossier(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_role text:=custom_private.request_role(); v_cash jsonb; v_costs jsonb; v_outsource jsonb; v_docs jsonb;
        v_config jsonb; v_notes jsonb; v_schedule jsonb;
begin
  if not factory_private.order_scope_allowed(p_order_id,'read') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.material_kind,x.material_name),'[]'::jsonb)
    into v_config from factory_private.order_material_configs x where x.order_id=p_order_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.document_kind,'name',x.file_name,
    'path',x.storage_path,'mime',x.mime_type,'version',x.version_label,'note',x.note,
    'confirmed',x.confirmed,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb)
    into v_docs from factory_private.order_documents x
   where x.order_id=p_order_id and (v_role='owner' or x.purchase_invoice_id is null);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
    into v_notes from factory_private.order_site_notes x where x.order_id=p_order_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'process',x.process_name,'supplier',x.supplier,
    'planned_date',x.planned_date,'received_date',x.received_date,'status',x.status,'quality_result',x.quality_result,
    'note',x.note,'actual_cost',case when v_role='owner' then x.actual_cost else null end,'created_at',x.created_at)
    order by x.created_at desc),'[]'::jsonb)
    into v_outsource from factory_private.outsource_jobs x where x.order_id=p_order_id;
  select jsonb_build_object('planned_start_date',w.planned_start_date,'delivery_date',w.delivery_date,
    'note',w.schedule_note) into v_schedule from factory_private.work_orders w where w.id=p_order_id;
  if v_role in ('owner','factory_manager') then
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.entry_kind,'date',x.entry_date,
      'amount',case when v_role='owner' then x.amount else null end,
      'method',x.method,'counterparty',x.counterparty,'note',x.note,
      'stage',x.payment_stage,'sequence',x.receipt_sequence) order by x.entry_date desc,x.created_at desc),'[]'::jsonb)
      into v_cash from factory_private.order_cash_entries x where x.order_id=p_order_id;
  else v_cash:='[]'::jsonb; end if;
  if v_role='owner' then
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'category',x.cost_category,'amount',x.amount,
      'source',x.source_type,'note',x.note,'created_at',x.created_at) order by x.created_at),'[]'::jsonb)
      into v_costs from factory_private.order_cost_entries x where x.order_id=p_order_id;
  else v_costs:='[]'::jsonb; end if;
  return jsonb_build_object('material_configs',v_config,'documents',v_docs,'site_notes',v_notes,
    'outsource',v_outsource,'cash_entries',v_cash,'cost_entries',v_costs,'schedule',coalesce(v_schedule,'{}'::jsonb));
end
$$;
alter function api.factory_order_dossier(uuid) owner to anju_custom_executor;
revoke all on function api.factory_order_dossier(uuid) from public,anon;
grant execute on function api.factory_order_dossier(uuid) to authenticated;

create or replace function api.factory_owner_record_public_cost(
  p_cost_month date,p_category text,p_amount numeric,p_note text,p_request_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_category text; v_item text;
begin
  perform custom_private.require_roles(array['owner']);
  if p_cost_month is null or p_amount is null or p_amount<=0 or p_request_id is null
     or length(btrim(coalesce(p_category,'')))=0 or length(btrim(p_category))>100 then
    raise exception using errcode='22023',message='factory_invalid_public_cost';
  end if;
  v_category:=case when p_category in ('房租','水电','固定人工','折旧','办公软件','营销推广','其他')
    then p_category else '其他' end;
  v_item:=case when p_category=v_category then '' else left(btrim(p_category),100) end;
  v_dup:=factory_private.claim_request('factory_owner_record_public_cost',p_request_id,
    jsonb_build_object('month',date_trunc('month',p_cost_month)::date,'category',p_category,'amount',p_amount,'note',p_note));
  if not v_dup then
    insert into public.fixed_costs(cost_month,category,amount,note,item,ownership,created_by,request_id)
    values(date_trunc('month',p_cost_month)::date,v_category,p_amount,left(coalesce(p_note,''),1000),
      v_item,'工厂',custom_private.request_uid(),p_request_id);
  end if;
  return jsonb_build_object('status','ok');
end
$$;
alter function api.factory_owner_record_public_cost(date,text,numeric,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_owner_record_public_cost(date,text,numeric,text,uuid) from public,anon;
grant execute on function api.factory_owner_record_public_cost(date,text,numeric,text,uuid) to authenticated;

create or replace function api.factory_record_inventory_movement_batch(
  p_movement_date date,p_rows jsonb,p_request_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_row jsonb; v_count integer:=0;
begin
  if custom_private.request_role() not in ('owner','factory_manager') or p_request_id is null
     or jsonb_typeof(coalesce(p_rows,'null'::jsonb))<>'array'
     or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>100 then
    raise exception using errcode='22023',message='factory_invalid_movement_batch';
  end if;
  v_dup:=factory_private.claim_request('factory_record_inventory_movement_batch',p_request_id,
    jsonb_build_object('date',p_movement_date,'rows',p_rows));
  if not v_dup then
    for v_row in select value from jsonb_array_elements(p_rows) loop
      if coalesce((v_row->>'quantity')::numeric,0)<=0 or coalesce((v_row->>'unit_price')::numeric,0)<0
         or nullif(v_row->>'material_id','') is null then
        raise exception using errcode='22023',message='factory_invalid_movement_batch_row';
      end if;
      perform api.factory_record_inventory_movement(
        coalesce(p_movement_date,current_date),'入库',(v_row->>'material_id')::uuid,
        (v_row->>'quantity')::numeric,coalesce((v_row->>'unit_price')::numeric,0),
        coalesce(v_row->>'supplier_source',''),null,'五金 / 辅料采购入库',
        coalesce(v_row->>'handled_by',''),coalesce(v_row->>'note',''),null,gen_random_uuid());
      v_count:=v_count+1;
    end loop;
  end if;
  return jsonb_build_object('status','ok','rows',case when v_dup then jsonb_array_length(p_rows) else v_count end);
end
$$;
alter function api.factory_record_inventory_movement_batch(date,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.factory_record_inventory_movement_batch(date,jsonb,uuid) from public,anon;
grant execute on function api.factory_record_inventory_movement_batch(date,jsonb,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
