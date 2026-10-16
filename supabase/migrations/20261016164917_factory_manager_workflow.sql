begin;

-- Additive factory-only schema changes. Legacy values and old RPCs remain valid.
alter table factory_private.work_orders
  drop constraint if exists work_orders_business_source_check;
alter table factory_private.work_orders
  add constraint work_orders_business_source_check check (business_source in ('门店定制','整装配套','外加工','渠道','代加工','门店','老客户介绍'));
alter table factory_private.work_orders
  add column if not exists channel_customer_name text not null default '',
  add column if not exists breakdown_designer_id uuid,
  add column if not exists breakdown_designer_name text not null default '',
  add column if not exists workshop_lead_id uuid,
  add column if not exists workshop_lead_name text not null default '';

alter table factory_private.materials drop constraint if exists materials_category_check;
alter table factory_private.materials add constraint materials_category_check
  check(category in ('五金','辅料','板材','基础物资','特殊物资','消耗品'));
alter table factory_private.order_documents drop constraint if exists order_documents_document_kind_check;
alter table factory_private.order_documents add constraint order_documents_document_kind_check
  check(document_kind in ('图纸','板材单','五金单','合同','报价单','变更单','其他资料','现场照片'));
alter table factory_private.order_cost_entries drop constraint if exists order_cost_entries_source_type_check;
alter table factory_private.order_cost_entries add constraint order_cost_entries_source_type_check
  check(source_type in ('inventory','attendance','owner_entry','reversal','outsourcing','purchase'));

create table if not exists factory_private.order_spec_profiles (
  order_id uuid primary key references factory_private.work_orders(id),
  board_specs jsonb not null default '[]'::jsonb check(jsonb_typeof(board_specs)='array'),
  hardware_brand text not null default '',
  hardware_details jsonb not null default '[]'::jsonb check(jsonb_typeof(hardware_details)='array'),
  special_items text not null default '',
  requirements text not null default '',
  updated_by uuid not null,
  updated_at timestamptz not null default now()
);
create table if not exists factory_private.order_purchase_costs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references factory_private.work_orders(id),
  cost_kind text not null check(cost_kind in ('板材','五金','外协','其他')),
  supplier text not null default '',
  bill_no text not null default '',
  bill_date date not null default current_date,
  lines jsonb not null default '[]'::jsonb check(jsonb_typeof(lines)='array'),
  amount numeric(14,2) not null check(amount>0),
  note text not null default '',
  created_by uuid not null,
  created_at timestamptz not null default now(),
  request_id uuid not null,
  unique(created_by,request_id)
);
create table if not exists factory_private.order_purchase_cost_documents (
  id uuid primary key default gen_random_uuid(),
  purchase_cost_id uuid not null references factory_private.order_purchase_costs(id),
  file_name text not null,
  storage_path text not null unique,
  mime_type text not null,
  file_size bigint not null check(file_size>0 and file_size<=31457280),
  created_by uuid not null,
  created_at timestamptz not null default now()
);

do $$ declare t text; begin
  foreach t in array array['order_spec_profiles','order_purchase_costs','order_purchase_cost_documents'] loop
    execute format('alter table factory_private.%I enable row level security',t);
    execute format('alter table factory_private.%I force row level security',t);
    execute format('drop policy if exists factory_executor_access on factory_private.%I',t);
    execute format('create policy factory_executor_access on factory_private.%I for all to anju_custom_executor using(true) with check(true)',t);
  end loop;
end $$;
grant select,insert,update on factory_private.order_spec_profiles,factory_private.order_purchase_costs,factory_private.order_purchase_cost_documents to anju_custom_executor;
revoke all on factory_private.order_spec_profiles,factory_private.order_purchase_costs,factory_private.order_purchase_cost_documents from public,anon,authenticated;

-- Managers may see only the order amount needed to run production, never order costs or margin.
drop function if exists api.factory_work_orders_safe();
create function api.factory_work_orders_safe()
returns table(id uuid,order_no text,customer_project text,business_source text,channel_customer_name text,order_date date,delivery_date date,current_process text,status text,order_amount numeric,completed_at timestamptz,note text)
language plpgsql stable security definer set search_path=''
as $$ begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select w.id,w.order_no,w.customer_project,w.business_source,w.channel_customer_name,w.order_date,w.delivery_date,w.current_process,w.status,w.order_amount,w.completed_at,w.note
  from factory_private.work_orders w order by w.order_date desc,w.created_at desc;
end $$;
alter function api.factory_work_orders_safe() owner to anju_custom_executor;
revoke all on function api.factory_work_orders_safe() from public,anon;
grant execute on function api.factory_work_orders_safe() to authenticated;

-- Order creation accepts the revised source names and optional channel customer text.
create or replace function api.owner_create_factory_work_order(
 p_order_no text,p_customer_project text,p_business_source text,p_order_date date,p_delivery_date date,
 p_order_amount numeric,p_note text,p_channel_customer_name text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_id uuid; v_dup boolean;
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_business_source not in ('渠道','代加工','门店','老客户介绍') or p_order_amount<0 or length(btrim(coalesce(p_order_no,'')))=0 or length(btrim(coalesce(p_customer_project,'')))=0 then
    raise exception using errcode='22023',message='factory_invalid_order';
  end if;
  if p_business_source='渠道' and length(btrim(coalesce(p_channel_customer_name,'')))=0 then raise exception using errcode='22023',message='factory_channel_customer_required'; end if;
  v_dup:=factory_private.claim_request('owner_create_factory_work_order_v2',p_request_id,jsonb_build_object('order_no',p_order_no,'customer_project',p_customer_project,'business_source',p_business_source,'order_date',p_order_date,'delivery_date',p_delivery_date,'order_amount',p_order_amount,'note',p_note,'channel_customer',p_channel_customer_name));
  if not v_dup then insert into factory_private.work_orders(order_no,customer_project,business_source,channel_customer_name,order_date,delivery_date,order_amount,note,created_by)
    values(left(btrim(p_order_no),80),left(btrim(p_customer_project),160),p_business_source,left(btrim(coalesce(p_channel_customer_name,'')),160),coalesce(p_order_date,current_date),p_delivery_date,p_order_amount,left(coalesce(p_note,''),1000),custom_private.request_uid()) returning id into v_id; end if;
  return jsonb_build_object('status','ok','id',v_id);
end $$;
alter function api.owner_create_factory_work_order(text,text,text,date,date,numeric,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.owner_create_factory_work_order(text,text,text,date,date,numeric,text,text,uuid) from public,anon;
grant execute on function api.owner_create_factory_work_order(text,text,text,date,date,numeric,text,text,uuid) to authenticated;

create or replace function api.factory_update_order_delivery(p_order_id uuid,p_delivery_date date,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_dup boolean;
begin
  if custom_private.request_role() not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_delivery_date is null or p_request_id is null then raise exception using errcode='22023',message='factory_delivery_date_required'; end if;
  v_dup:=factory_private.claim_request('factory_update_order_delivery',p_request_id,jsonb_build_object('order_id',p_order_id,'delivery_date',p_delivery_date,'note',p_note));
  if not v_dup then update factory_private.work_orders set delivery_date=p_delivery_date,note=left(coalesce(p_note,''),1000),updated_at=now() where id=p_order_id; end if;
  return jsonb_build_object('status','ok');
end $$;
alter function api.factory_update_order_delivery(uuid,date,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_update_order_delivery(uuid,date,text,uuid) from public,anon;
grant execute on function api.factory_update_order_delivery(uuid,date,text,uuid) to authenticated;

create or replace function api.factory_order_spec_profile(p_order_id uuid)
returns table(board_specs jsonb,hardware_brand text,hardware_details jsonb,special_items text,requirements text)
language plpgsql stable security definer set search_path=''
as $$ begin
  if custom_private.request_role() not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'read') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select coalesce(s.board_specs,'[]'::jsonb),coalesce(s.hardware_brand,''),coalesce(s.hardware_details,'[]'::jsonb),coalesce(s.special_items,''),coalesce(s.requirements,'') from (select 1) z left join factory_private.order_spec_profiles s on s.order_id=p_order_id;
end $$;
alter function api.factory_order_spec_profile(uuid) owner to anju_custom_executor;
revoke all on function api.factory_order_spec_profile(uuid) from public,anon;
grant execute on function api.factory_order_spec_profile(uuid) to authenticated;

create or replace function api.factory_register_order_document(p_order_id uuid,p_kind text,p_file_name text,p_storage_path text,p_mime_type text,p_file_size bigint,p_version text,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_dup boolean; v_id uuid;
begin
  if custom_private.request_role() not in ('owner','factory_manager') or p_request_id is null or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_kind not in ('图纸','板材单','五金单','合同','报价单','变更单','其他资料','现场照片') or p_file_size is null or p_file_size<=0 or p_file_size>31457280 or not factory_private.order_storage_allowed(p_order_id,p_storage_path,'write') then raise exception using errcode='42501',message='factory_document_forbidden'; end if;
  v_dup:=factory_private.claim_request('factory_register_order_document',p_request_id,jsonb_build_object('order',p_order_id,'kind',p_kind,'path',p_storage_path,'name',p_file_name,'mime',p_mime_type,'size',p_file_size,'version',p_version,'note',p_note));
  if not v_dup then insert into factory_private.order_documents(order_id,document_kind,file_name,storage_path,mime_type,file_size,version_label,note,created_by,request_id)
    values(p_order_id,p_kind,left(p_file_name,255),p_storage_path,p_mime_type,p_file_size,left(coalesce(p_version,''),60),left(coalesce(p_note,''),1000),custom_private.request_uid(),p_request_id) returning id into v_id; end if;
  return jsonb_build_object('status','ok','id',v_id);
end $$;
alter function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) from public,anon;
grant execute on function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) to authenticated;

create or replace function api.factory_save_order_spec_profile(p_order_id uuid,p_board_specs jsonb,p_hardware_brand text,p_hardware_details jsonb,p_special_items text,p_requirements text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_dup boolean;
begin
  if custom_private.request_role() not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if jsonb_typeof(coalesce(p_board_specs,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_hardware_details,'[]'::jsonb))<>'array' then raise exception using errcode='22023',message='factory_invalid_order_specs'; end if;
  v_dup:=factory_private.claim_request('factory_save_order_spec_profile',p_request_id,jsonb_build_object('order_id',p_order_id,'board_specs',p_board_specs,'hardware_brand',p_hardware_brand,'hardware_details',p_hardware_details,'special_items',p_special_items,'requirements',p_requirements));
  if not v_dup then insert into factory_private.order_spec_profiles(order_id,board_specs,hardware_brand,hardware_details,special_items,requirements,updated_by,updated_at)
    values(p_order_id,coalesce(p_board_specs,'[]'::jsonb),left(coalesce(p_hardware_brand,''),120),coalesce(p_hardware_details,'[]'::jsonb),left(coalesce(p_special_items,''),4000),left(coalesce(p_requirements,''),4000),custom_private.request_uid(),now())
    on conflict(order_id) do update set board_specs=excluded.board_specs,hardware_brand=excluded.hardware_brand,hardware_details=excluded.hardware_details,special_items=excluded.special_items,requirements=excluded.requirements,updated_by=excluded.updated_by,updated_at=now(); end if;
  return jsonb_build_object('status','ok');
end $$;
alter function api.factory_save_order_spec_profile(uuid,jsonb,text,jsonb,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_save_order_spec_profile(uuid,jsonb,text,jsonb,text,text,uuid) from public,anon;
grant execute on function api.factory_save_order_spec_profile(uuid,jsonb,text,jsonb,text,text,uuid) to authenticated;

create or replace function api.owner_assign_factory_work_order_v2(p_order_id uuid,p_store_designer_id uuid,p_breakdown_designer_id uuid,p_workshop_lead_id uuid,p_store_designer_name text,p_breakdown_designer_name text,p_workshop_lead_name text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_dup boolean;
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if not exists(select 1 from factory_private.work_orders where id=p_order_id) then raise exception using errcode='P0002',message='factory_order_not_found'; end if;
  if p_store_designer_id is not null and not exists(select 1 from auth.users where id=p_store_designer_id and raw_app_meta_data->>'role' in ('sales','designer')) then raise exception using errcode='22023',message='factory_assignment_invalid'; end if;
  if p_breakdown_designer_id is not null and not exists(select 1 from auth.users where id=p_breakdown_designer_id and raw_app_meta_data->>'role' in ('sales','designer')) then raise exception using errcode='22023',message='factory_assignment_invalid'; end if;
  if p_workshop_lead_id is not null and not exists(select 1 from auth.users where id=p_workshop_lead_id and raw_app_meta_data->>'role' in ('foreman','factory_manager')) then raise exception using errcode='22023',message='factory_assignment_invalid'; end if;
  v_dup:=factory_private.claim_request('owner_assign_factory_work_order_v2',p_request_id,jsonb_build_object('order_id',p_order_id,'store',p_store_designer_id,'breakdown',p_breakdown_designer_id,'lead',p_workshop_lead_id,'store_name',p_store_designer_name,'breakdown_name',p_breakdown_designer_name,'lead_name',p_workshop_lead_name));
  if not v_dup then update factory_private.work_orders set designer_id=p_store_designer_id,designer_name=left(coalesce(p_store_designer_name,''),120),breakdown_designer_id=p_breakdown_designer_id,breakdown_designer_name=left(coalesce(p_breakdown_designer_name,''),120),foreman_id=p_workshop_lead_id,foreman_name=left(coalesce(p_workshop_lead_name,''),120),workshop_lead_id=p_workshop_lead_id,workshop_lead_name=left(coalesce(p_workshop_lead_name,''),120),updated_at=now() where id=p_order_id; end if;
  return jsonb_build_object('status','ok');
end $$;
alter function api.owner_assign_factory_work_order_v2(uuid,uuid,uuid,uuid,text,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.owner_assign_factory_work_order_v2(uuid,uuid,uuid,uuid,text,text,text,uuid) from public,anon;
grant execute on function api.owner_assign_factory_work_order_v2(uuid,uuid,uuid,uuid,text,text,text,uuid) to authenticated;

create or replace function api.factory_record_order_purchase_cost(p_order_id uuid,p_cost_kind text,p_supplier text,p_bill_no text,p_bill_date date,p_lines jsonb,p_note text,p_documents jsonb,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_actor uuid:=custom_private.request_uid(); v_dup boolean; v_id uuid; v_total numeric(14,2); v_category text; v_line jsonb; v_no integer:=0; v_qty numeric; v_price numeric; v_amount numeric;
begin
  if custom_private.request_role() not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_cost_kind not in ('板材','五金','外协','其他') or jsonb_typeof(coalesce(p_lines,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_lines,'[]'::jsonb))=0 then raise exception using errcode='22023',message='factory_purchase_invalid'; end if;
  if exists(select 1 from jsonb_array_elements(p_lines) x where length(btrim(coalesce(x->>'product','')))=0 or coalesce((x->>'amount')::numeric,0)<=0) then raise exception using errcode='22023',message='factory_purchase_line_invalid'; end if;
  select round(sum((x->>'amount')::numeric),2) into v_total from jsonb_array_elements(p_lines) x;
  if v_total<=0 then raise exception using errcode='22023',message='factory_purchase_invalid'; end if;
  v_dup:=factory_private.claim_request('factory_record_order_purchase_cost',p_request_id,jsonb_build_object('order_id',p_order_id,'kind',p_cost_kind,'supplier',p_supplier,'bill_no',p_bill_no,'date',p_bill_date,'lines',p_lines,'note',p_note,'documents',p_documents));
  if not v_dup then
    insert into factory_private.order_purchase_costs(order_id,cost_kind,supplier,bill_no,bill_date,lines,amount,note,created_by,request_id)
    values(p_order_id,p_cost_kind,left(coalesce(p_supplier,''),160),left(coalesce(p_bill_no,''),120),coalesce(p_bill_date,current_date),p_lines,v_total,left(coalesce(p_note,''),2000),v_actor,p_request_id) returning id into v_id;
    v_category:=case p_cost_kind when '外协' then '外协' when '其他' then '其他' else p_cost_kind end;
    insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,source_id,note,created_by,request_id)
    values(p_order_id,v_category,v_total,'purchase',v_id,coalesce(p_note,''),v_actor,gen_random_uuid());
    for v_line in select value from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) loop
      if not factory_private.order_storage_allowed(p_order_id,v_line->>'storage_path','write') or coalesce((v_line->>'file_size')::bigint,0)<=0 or (v_line->>'file_size')::bigint>31457280 then raise exception using errcode='42501',message='factory_document_forbidden'; end if;
      insert into factory_private.order_purchase_cost_documents(purchase_cost_id,file_name,storage_path,mime_type,file_size,created_by)
      values(v_id,left(coalesce(v_line->>'file_name','原单'),255),v_line->>'storage_path',coalesce(v_line->>'mime_type','application/octet-stream'),(v_line->>'file_size')::bigint,v_actor);
    end loop;
  end if;
  return jsonb_build_object('status','ok','amount',v_total);
end $$;
alter function api.factory_record_order_purchase_cost(uuid,text,text,text,date,jsonb,text,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.factory_record_order_purchase_cost(uuid,text,text,text,date,jsonb,text,jsonb,uuid) from public,anon;
grant execute on function api.factory_record_order_purchase_cost(uuid,text,text,text,date,jsonb,text,jsonb,uuid) to authenticated;

create or replace function api.factory_order_purchase_costs(p_order_id uuid)
returns table(id uuid,cost_kind text,supplier text,bill_no text,bill_date date,lines jsonb,amount numeric,note text,documents jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$ begin
  if custom_private.request_role() not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'read') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select p.id,p.cost_kind,p.supplier,p.bill_no,p.bill_date,p.lines,p.amount,p.note,
    coalesce((select jsonb_agg(jsonb_build_object('name',d.file_name,'path',d.storage_path,'mime',d.mime_type) order by d.created_at) from factory_private.order_purchase_cost_documents d where d.purchase_cost_id=p.id),'[]'::jsonb),p.created_at
  from factory_private.order_purchase_costs p where p.order_id=p_order_id order by p.bill_date desc,p.created_at desc;
end $$;
alter function api.factory_order_purchase_costs(uuid) owner to anju_custom_executor;
revoke all on function api.factory_order_purchase_costs(uuid) from public,anon;
grant execute on function api.factory_order_purchase_costs(uuid) to authenticated;

-- Fixed cost rows are visible to factory managers; profit/payroll APIs remain owner-only.
create or replace function api.factory_manager_fixed_costs(p_month date default null)
returns table(id uuid,cost_month date,category text,item text,amount numeric,ownership text,note text)
language plpgsql stable security definer set search_path=''
as $$ begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select f.id,f.cost_month,f.category,f.item,f.amount,f.ownership,f.note from public.fixed_costs f
    where f.ownership='工厂' and (p_month is null or date_trunc('month',f.cost_month)::date=date_trunc('month',p_month)::date)
    order by f.cost_month desc,f.created_at desc;
end $$;
alter function api.factory_manager_fixed_costs(date) owner to anju_custom_executor;
revoke all on function api.factory_manager_fixed_costs(date) from public,anon;
grant execute on function api.factory_manager_fixed_costs(date) to authenticated;

create or replace function api.factory_owner_record_public_cost(p_cost_month date,p_category text,p_amount numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_dup boolean; v_category text; v_item text; v_role text:=custom_private.request_role();
begin
  if v_role not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_cost_month is null or p_amount is null or p_amount<=0 or p_request_id is null or length(btrim(coalesce(p_category,'')))=0 or length(btrim(p_category))>100 then raise exception using errcode='22023',message='factory_invalid_public_cost'; end if;
  v_category:=case when p_category in ('房租','水电','固定人工','折旧','办公软件','营销推广','其他') then p_category else '其他' end;
  v_item:=case when p_category=v_category then '' else left(btrim(p_category),100) end;
  v_dup:=factory_private.claim_request('factory_owner_record_public_cost',p_request_id,jsonb_build_object('month',date_trunc('month',p_cost_month)::date,'category',p_category,'amount',p_amount,'note',p_note));
  if not v_dup then insert into public.fixed_costs(cost_month,category,amount,note,item,ownership,created_by,request_id)
    values(date_trunc('month',p_cost_month)::date,v_category,p_amount,left(coalesce(p_note,''),1000),v_item,'工厂',custom_private.request_uid(),p_request_id); end if;
  return jsonb_build_object('status','ok');
end $$;
alter function api.factory_owner_record_public_cost(date,text,numeric,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_owner_record_public_cost(date,text,numeric,text,uuid) from public,anon;
grant execute on function api.factory_owner_record_public_cost(date,text,numeric,text,uuid) to authenticated;

create or replace function api.factory_owner_record_public_cost(p_cost_month date,p_category text,p_item text,p_amount numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_dup boolean; v_category text; v_item text; v_role text:=custom_private.request_role();
begin
  if v_role not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_cost_month is null or p_amount is null or p_amount<=0 or p_request_id is null or length(btrim(coalesce(p_category,'')))=0 or length(btrim(p_category))>100 or length(btrim(coalesce(p_item,'')))>160 then raise exception using errcode='22023',message='factory_invalid_public_cost'; end if;
  v_category:=case when p_category in ('房租','水电','固定人工','折旧','办公软件','营销推广','其他') then p_category else '其他' end;
  v_item:=case when p_category=v_category then left(btrim(coalesce(p_item,'')),160) else concat_ws(' · ',left(btrim(p_category),100),nullif(left(btrim(coalesce(p_item,'')),160),'')) end;
  v_dup:=factory_private.claim_request('factory_owner_record_public_cost_v2',p_request_id,jsonb_build_object('month',date_trunc('month',p_cost_month)::date,'category',p_category,'item',p_item,'amount',p_amount,'note',p_note));
  if not v_dup then insert into public.fixed_costs(cost_month,category,amount,note,item,ownership,created_by,request_id)
    values(date_trunc('month',p_cost_month)::date,v_category,p_amount,left(coalesce(p_note,''),1000),v_item,'工厂',custom_private.request_uid(),p_request_id); end if;
  return jsonb_build_object('status','ok');
end $$;
alter function api.factory_owner_record_public_cost(date,text,text,numeric,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_owner_record_public_cost(date,text,text,numeric,text,uuid) from public,anon;
grant execute on function api.factory_owner_record_public_cost(date,text,text,numeric,text,uuid) to authenticated;

-- Allow authorized order participants to view private bill images/files.
drop policy if exists factory_purchase_cost_files_read on storage.objects;
create policy factory_purchase_cost_files_read on storage.objects for select to authenticated
using(bucket_id='factory-files' and exists(select 1 from factory_private.order_purchase_cost_documents d join factory_private.order_purchase_costs p on p.id=d.purchase_cost_id where d.storage_path=name and factory_private.order_scope_allowed(p.order_id,'read')));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('factory-files','factory-files',false,31457280,array['image/jpeg','image/png','image/webp','image/gif','application/pdf','text/csv','text/plain','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/msword'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

notify pgrst, 'reload schema';
commit;
