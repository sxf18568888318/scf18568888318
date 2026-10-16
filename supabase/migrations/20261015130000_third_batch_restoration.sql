begin;

-- Additive customer fields for the renovation customer workbench. Existing rows
-- remain unchanged; new profile data is isolated in extension tables.
alter table public.customers
  add column if not exists designer_display_name text not null default '',
  add column if not exists foreman_display_name text not null default '';

create table if not exists public.reno_customer_profiles (
  customer_id uuid primary key references public.customers(id),
  needs text not null default '',
  survey_notes text not null default '',
  preferences text not null default '',
  updated_by uuid not null,
  updated_at timestamptz not null default now()
);
create table if not exists public.reno_customer_documents (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  document_kind text not null check(document_kind in ('纸质合同','户型图','变更单','沟通记录','其他资料')),
  file_name text not null,
  storage_path text not null,
  mime_type text not null,
  file_size bigint not null check(file_size>0 and file_size<=20971520),
  note text not null default '',
  created_by uuid not null,
  created_at timestamptz not null default now(),
  request_id uuid not null unique
);
create table if not exists public.reno_extension_receipts (
  request_id uuid primary key, actor_id uuid not null, operation text not null, entity_id uuid,
  payload_hash text not null, response jsonb not null, created_at timestamptz not null default now()
);
alter table public.reno_customer_profiles enable row level security;
alter table public.reno_customer_profiles force row level security;
drop policy if exists reno_customer_profiles_executor on public.reno_customer_profiles;
create policy reno_customer_profiles_executor on public.reno_customer_profiles for all to anju_custom_executor using(true) with check(true);
alter table public.reno_customer_documents enable row level security;
alter table public.reno_customer_documents force row level security;
drop policy if exists reno_customer_documents_executor on public.reno_customer_documents;
create policy reno_customer_documents_executor on public.reno_customer_documents for all to anju_custom_executor using(true) with check(true);
alter table public.reno_extension_receipts enable row level security;
alter table public.reno_extension_receipts force row level security;
drop policy if exists reno_extension_receipts_executor on public.reno_extension_receipts;
create policy reno_extension_receipts_executor on public.reno_extension_receipts for all to anju_custom_executor using(true) with check(true);
grant select,insert,update on public.reno_customer_profiles,public.reno_customer_documents,public.reno_extension_receipts to anju_custom_executor;
revoke all on public.reno_customer_profiles,public.reno_customer_documents,public.reno_extension_receipts from public,anon,authenticated;

create or replace function api.reno_set_customer_assignment_labels(p_customer_id uuid,p_designer_name text,p_foreman_name text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_role text:=custom_private.request_role(); v_uid uuid:=custom_private.request_uid(); v_old jsonb; v_new jsonb;
begin
  perform custom_private.require_roles(array['owner','designer']);
  if p_request_id is null or not custom_private.reno_customer_allowed(p_customer_id) then raise exception using errcode='42501',message='reno_customer_forbidden'; end if;
  v_new:=jsonb_build_object('customer_id',p_customer_id,'designer_name',left(coalesce(p_designer_name,''),120),'foreman_name',left(coalesce(p_foreman_name,''),120));
  select to_jsonb(c.*) into v_old from public.customers c where c.id=p_customer_id and c.business_line in ('reno','reno+custom');
  if v_old is null then raise exception using errcode='42501',message='reno_customer_forbidden'; end if;
  insert into public.reno_extension_receipts(request_id,operation,actor_id,entity_id,payload_hash,response)
  values(p_request_id,'customer_assignment_labels',v_uid,p_customer_id,md5(v_new::text),jsonb_build_object('status','saved'))
  on conflict(request_id) do nothing;
  if not found then
    if not exists(select 1 from public.reno_extension_receipts r where r.request_id=p_request_id and r.actor_id=v_uid and r.operation='customer_assignment_labels' and r.entity_id=p_customer_id and r.payload_hash=md5(v_new::text)) then raise exception using errcode='23505',message='request_id_conflict'; end if;
    return jsonb_build_object('status','existing');
  end if;
  update public.customers set designer_display_name=left(coalesce(p_designer_name,''),120),foreman_display_name=left(coalesce(p_foreman_name,''),120)
  where id=p_customer_id and business_line in ('reno','reno+custom');
  return jsonb_build_object('status','saved');
end $$;

create or replace function api.reno_customer_profile_details(p_customer_id uuid)
returns table(customer_id uuid,needs text,survey_notes text,preferences text,designer_display_name text,foreman_display_name text,documents jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
  if not custom_private.reno_customer_allowed(p_customer_id) then raise exception using errcode='42501',message='reno_customer_forbidden'; end if;
  return query select c.id,coalesce(p.needs,''),coalesce(p.survey_notes,''),coalesce(p.preferences,''),c.designer_display_name,c.foreman_display_name,
    coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'kind',d.document_kind,'file_name',d.file_name,'path',d.storage_path,'mime_type',d.mime_type,'file_size',d.file_size,'note',d.note,'created_at',d.created_at) order by d.created_at desc) from public.reno_customer_documents d where d.customer_id=c.id),'[]'::jsonb)
  from public.customers c left join public.reno_customer_profiles p on p.customer_id=c.id where c.id=p_customer_id and c.business_line in ('reno','reno+custom');
end $$;

create or replace function api.reno_save_customer_profile(p_customer_id uuid,p_needs text,p_survey_notes text,p_preferences text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
  declare v_uid uuid:=custom_private.request_uid(); v_payload jsonb; v_response jsonb:=jsonb_build_object('status','saved'); v_existing public.reno_extension_receipts%rowtype;
begin
  perform custom_private.require_roles(array['owner','designer']);
  if p_request_id is null or not custom_private.reno_customer_allowed(p_customer_id) then raise exception using errcode='42501',message='reno_customer_forbidden'; end if;
  v_payload:=jsonb_build_object('customer',p_customer_id,'needs',left(coalesce(p_needs,''),4000),'survey',left(coalesce(p_survey_notes,''),4000),'preferences',left(coalesce(p_preferences,''),4000));
  select * into v_existing from public.reno_extension_receipts where request_id=p_request_id;
  if found then if v_existing.actor_id<>v_uid or v_existing.operation<>'customer_profile_save' or v_existing.payload_hash<>md5(v_payload::text) then raise exception using errcode='23505',message='request_id_conflict'; end if; return coalesce(v_existing.response,v_response); end if;
  insert into public.reno_customer_profiles(customer_id,needs,survey_notes,preferences,updated_by,updated_at)
  values(p_customer_id,left(coalesce(p_needs,''),4000),left(coalesce(p_survey_notes,''),4000),left(coalesce(p_preferences,''),4000),v_uid,now())
  on conflict(customer_id) do update set needs=excluded.needs,survey_notes=excluded.survey_notes,preferences=excluded.preferences,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
  insert into public.reno_extension_receipts(request_id,operation,actor_id,entity_id,payload_hash,response) values(p_request_id,'customer_profile_save',v_uid,p_customer_id,md5(v_payload::text),v_response);
  return v_response;
end $$;

create or replace function api.reno_register_customer_document(p_customer_id uuid,p_kind text,p_file_name text,p_storage_path text,p_mime_type text,p_file_size bigint,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_uid uuid:=custom_private.request_uid(); v_id uuid; v_kind text:=left(coalesce(p_kind,''),40); v_payload jsonb; v_old public.reno_customer_documents%rowtype;
begin
  perform custom_private.require_roles(array['owner','designer']);
  if p_request_id is null or not custom_private.reno_customer_allowed(p_customer_id) or v_kind not in ('纸质合同','户型图','变更单','沟通记录','其他资料') then raise exception using errcode='42501',message='reno_document_forbidden'; end if;
  if p_file_size is null or p_file_size<=0 or p_file_size>20971520 or p_mime_type not in ('image/jpeg','image/png','image/webp','application/pdf') or not custom_private.reno_storage_allowed(p_storage_path,'write') then raise exception using errcode='42501',message='reno_document_path_forbidden'; end if;
  v_payload:=jsonb_build_object('customer',p_customer_id,'kind',v_kind,'path',p_storage_path,'name',p_file_name,'mime',p_mime_type,'size',p_file_size,'note',p_note);
  select * into v_old from public.reno_customer_documents where request_id=p_request_id;
  if found then if v_old.created_by<>v_uid or v_old.customer_id<>p_customer_id or v_old.storage_path<>p_storage_path then raise exception using errcode='23505',message='request_id_conflict'; end if; return jsonb_build_object('status','existing','id',v_old.id); end if;
  insert into public.reno_customer_documents(customer_id,document_kind,file_name,storage_path,mime_type,file_size,note,created_by,request_id)
  values(p_customer_id,v_kind,left(p_file_name,255),p_storage_path,p_mime_type,p_file_size,left(coalesce(p_note,''),1000),v_uid,p_request_id) returning id into v_id;
  return jsonb_build_object('status','saved','id',v_id);
end $$;

create or replace function api.reno_update_customer_stage(p_customer_id uuid,p_status text,p_stage text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
  declare v_uid uuid:=custom_private.request_uid(); v_old_status text; v_old_stage text; v_payload jsonb; v_receipt public.reno_extension_receipts%rowtype;
begin
  perform custom_private.require_roles(array['owner','designer']);
  if p_request_id is null or not custom_private.reno_customer_allowed(p_customer_id) or p_status not in ('线索','量房','报价中','已签约','施工中','已完工','已结算','搁置') then raise exception using errcode='42501',message='reno_customer_forbidden'; end if;
  if p_status in ('已签约','施工中','已完工','已结算') and not exists(select 1 from public.reno_orders o where o.customer_id=p_customer_id and (p_status not in ('已完工','已结算') or o.completed_at is not null)) then raise exception using errcode='42501',message='reno_stage_requires_order_state'; end if;
  v_payload:=jsonb_build_object('customer',p_customer_id,'status',p_status,'stage',left(coalesce(p_stage,''),120));
  select * into v_receipt from public.reno_extension_receipts where request_id=p_request_id;
  if found then if v_receipt.actor_id<>v_uid or v_receipt.operation<>'customer_stage_update' or v_receipt.payload_hash<>md5(v_payload::text) then raise exception using errcode='23505',message='request_id_conflict'; end if; return coalesce(v_receipt.response,jsonb_build_object('status','existing')); end if;
  select business_status,stage into v_old_status,v_old_stage from public.customers where id=p_customer_id and business_line in ('reno','reno+custom') for update;
  if not found then raise exception using errcode='42501',message='reno_customer_forbidden'; end if;
  update public.customers set business_status=p_status,stage=left(coalesce(p_stage,''),120) where id=p_customer_id;
  insert into public.reno_extension_receipts(request_id,operation,actor_id,entity_id,payload_hash,response) values(p_request_id,'customer_stage_update',v_uid,p_customer_id,md5(v_payload::text),jsonb_build_object('status','saved'));
  return jsonb_build_object('status','saved');
end $$;

-- Fixed monthly costs are saved to the shared, existing ledger with the
-- renovation ownership tag. This feeds the existing renovation net-profit lane.
create or replace function api.owner_reno_fixed_costs(p_month date default null)
returns table(id uuid,cost_month date,category text,amount numeric,item text,note text,reverses_id uuid)
language plpgsql stable security definer set search_path='' as $$
begin
  perform custom_private.require_roles(array['owner']);
  return query select f.id,f.cost_month,f.category,f.amount,f.item,f.note,f.reverses_id from public.fixed_costs f
   where f.ownership='整装' and (p_month is null or date_trunc('month',f.cost_month)::date=date_trunc('month',p_month)::date)
   order by f.cost_month desc,f.created_at desc;
end $$;

-- Renovation customer files use the existing private reno-files bucket and its
-- owner/designer customer path. No public URLs are created.

-- Factory detail extensions: all added rows start empty. Existing order,
-- inventory, attendance, cost, and payroll rows are not updated.
alter table factory_private.work_orders
  add column if not exists designer_id uuid references auth.users(id),
  add column if not exists foreman_id uuid references auth.users(id),
  add column if not exists designer_name text not null default '',
  add column if not exists foreman_name text not null default '';
create index if not exists factory_work_orders_designer_idx on factory_private.work_orders(designer_id);
create index if not exists factory_work_orders_foreman_idx on factory_private.work_orders(foreman_id);

create table if not exists factory_private.order_material_configs (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references factory_private.work_orders(id),
  material_name text not null, spec text not null default '', unit text not null default '', planned_quantity numeric(14,3) not null default 0 check(planned_quantity>=0),
  material_kind text not null default '板材' check(material_kind in ('板材','五金','辅料')), note text not null default '',
  created_by uuid not null, updated_at timestamptz not null default now(), unique(order_id,material_name,spec,material_kind)
);
create table if not exists factory_private.order_documents (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references factory_private.work_orders(id),
  document_kind text not null check(document_kind in ('图纸','板材单','五金单','合同','变更单','其他资料')),
  file_name text not null, storage_path text not null, mime_type text not null, file_size bigint not null check(file_size>0 and file_size<=31457280),
  version_label text not null default '', note text not null default '', confirmed boolean not null default false,
  created_by uuid not null, created_at timestamptz not null default now(), request_id uuid not null unique
);
create table if not exists factory_private.order_cash_entries (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references factory_private.work_orders(id),
  entry_kind text not null check(entry_kind in ('收款','付款')), entry_date date not null default current_date,
  amount numeric(14,2) not null check(amount>0), method text not null default '', counterparty text not null default '',
  note text not null default '', created_by uuid not null, created_at timestamptz not null default now(), request_id uuid not null unique
);
create table if not exists factory_private.outsource_jobs (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references factory_private.work_orders(id),
  process_name text not null, supplier text not null default '', planned_date date, received_date date,
  status text not null default '待送检' check(status in ('待送检','加工中','待验货','已验收','返工')),
  quality_result text not null default '', actual_cost numeric(14,2) check(actual_cost is null or actual_cost>=0),
  note text not null default '', created_by uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), request_id uuid not null unique
);
create table if not exists factory_private.order_site_notes (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references factory_private.work_orders(id),
  note_kind text not null default '现场备注' check(note_kind in ('接单要求','特殊工艺','现场备注','验货')), content text not null,
  created_by uuid not null, created_at timestamptz not null default now(), request_id uuid not null unique
);
do $$ declare t text; begin
  foreach t in array array['order_material_configs','order_documents','order_cash_entries','outsource_jobs','order_site_notes'] loop
    execute format('alter table factory_private.%I enable row level security',t);
    execute format('alter table factory_private.%I force row level security',t);
    execute format('drop policy if exists factory_executor_access on factory_private.%I',t);
    execute format('create policy factory_executor_access on factory_private.%I for all to anju_custom_executor using(true) with check(true)',t);
  end loop;
end $$;
grant select,insert,update on factory_private.order_material_configs,factory_private.order_documents,factory_private.order_cash_entries,factory_private.outsource_jobs,factory_private.order_site_notes to anju_custom_executor;
revoke all on factory_private.order_material_configs,factory_private.order_documents,factory_private.order_cash_entries,factory_private.outsource_jobs,factory_private.order_site_notes from public,anon,authenticated;

alter table factory_private.order_cost_entries drop constraint if exists order_cost_entries_source_type_check;
alter table factory_private.order_cost_entries add constraint order_cost_entries_source_type_check check(source_type in ('inventory','attendance','owner_entry','reversal','outsourcing'));

create or replace function factory_private.order_scope_allowed(p_order_id uuid,p_action text default 'read')
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from factory_private.work_orders w where w.id=p_order_id and (
   custom_private.request_role() in ('owner','factory_manager')
   or (custom_private.request_role()='designer' and w.designer_id=custom_private.request_uid())
   or (custom_private.request_role()='foreman' and w.foreman_id=custom_private.request_uid() and (p_action='read' or p_action='progress'))
 ))
$$;
alter function factory_private.order_scope_allowed(uuid,text) owner to postgres;
revoke all on function factory_private.order_scope_allowed(uuid,text) from public,anon;
grant execute on function factory_private.order_scope_allowed(uuid,text) to anju_custom_executor;
grant usage on schema factory_private to authenticated;
grant execute on function factory_private.order_scope_allowed(uuid,text) to authenticated;

create or replace function api.factory_assignment_users()
returns table(user_id uuid,role_name text,display_name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 return query select u.id,case u.raw_app_meta_data->>'role' when 'sales' then 'designer' when 'designer' then 'designer' when 'foreman' then 'foreman' when 'factory_manager' then 'factory_manager' else u.raw_app_meta_data->>'role' end,
   coalesce(nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),case u.raw_app_meta_data->>'role' when 'sales' then '设计师' when 'designer' then '设计师' when 'foreman' then '工长' else '工厂人员' end)
 from auth.users u where u.raw_app_meta_data->>'role' in ('sales','designer','foreman','factory_manager') order by 2,3;
end $$;

create or replace function api.owner_assign_factory_work_order(p_order_id uuid,p_designer_id uuid,p_foreman_id uuid,p_designer_name text,p_foreman_name text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean;
begin
 if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_request_id is null or not exists(select 1 from factory_private.work_orders where id=p_order_id) then raise exception using errcode='22023',message='factory_order_not_found'; end if;
 if p_designer_id is not null and not exists(select 1 from auth.users u where u.id=p_designer_id and u.raw_app_meta_data->>'role' in ('sales','designer')) then raise exception using errcode='22023',message='factory_assignment_invalid'; end if;
 if p_foreman_id is not null and not exists(select 1 from auth.users u where u.id=p_foreman_id and u.raw_app_meta_data->>'role'='foreman') then raise exception using errcode='22023',message='factory_assignment_invalid'; end if;
 v_dup:=factory_private.claim_request('owner_assign_factory_work_order',p_request_id,jsonb_build_object('order_id',p_order_id,'designer_id',p_designer_id,'foreman_id',p_foreman_id,'designer_name',p_designer_name,'foreman_name',p_foreman_name));
 if not v_dup then update factory_private.work_orders set designer_id=p_designer_id,foreman_id=p_foreman_id,designer_name=left(coalesce(p_designer_name,''),120),foreman_name=left(coalesce(p_foreman_name,''),120),updated_at=now() where id=p_order_id; end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_visible_work_orders()
returns table(id uuid,order_no text,customer_project text,business_source text,order_date date,delivery_date date,current_process text,status text,completed_at timestamptz,note text,designer_name text,foreman_name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if custom_private.request_role() not in ('owner','factory_manager','designer','foreman') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 return query select w.id,w.order_no,w.customer_project,w.business_source,w.order_date,w.delivery_date,w.current_process,w.status,w.completed_at,w.note,w.designer_name,w.foreman_name
 from factory_private.work_orders w where factory_private.order_scope_allowed(w.id,'read') order by w.order_date desc,w.created_at desc;
end $$;

create or replace function api.factory_order_dossier(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_role text:=custom_private.request_role(); v_costs jsonb; v_cash jsonb; v_outsource jsonb; v_docs jsonb; v_config jsonb; v_notes jsonb;
begin
 if not factory_private.order_scope_allowed(p_order_id,'read') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.material_kind,x.material_name),'[]'::jsonb) into v_config from factory_private.order_material_configs x where x.order_id=p_order_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.document_kind,'name',x.file_name,'path',x.storage_path,'mime',x.mime_type,'version',x.version_label,'note',x.note,'confirmed',x.confirmed,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into v_docs from factory_private.order_documents x where x.order_id=p_order_id;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_notes from factory_private.order_site_notes x where x.order_id=p_order_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'process',x.process_name,'supplier',x.supplier,'planned_date',x.planned_date,'received_date',x.received_date,'status',x.status,'quality_result',x.quality_result,'note',x.note,'actual_cost',case when v_role='owner' then x.actual_cost else null end,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into v_outsource from factory_private.outsource_jobs x where x.order_id=p_order_id;
 if v_role='owner' then
   select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.entry_kind,'date',x.entry_date,'amount',x.amount,'method',x.method,'counterparty',x.counterparty,'note',x.note) order by x.entry_date desc),'[]'::jsonb) into v_cash from factory_private.order_cash_entries x where x.order_id=p_order_id;
   select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'category',x.cost_category,'amount',x.amount,'source',x.source_type,'note',x.note,'created_at',x.created_at) order by x.created_at),'[]'::jsonb) into v_costs from factory_private.order_cost_entries x where x.order_id=p_order_id;
 else v_cash:='[]'::jsonb; v_costs:='[]'::jsonb; end if;
 return jsonb_build_object('material_configs',v_config,'documents',v_docs,'site_notes',v_notes,'outsource',v_outsource,'cash_entries',v_cash,'cost_entries',v_costs);
end $$;

create or replace function api.factory_save_order_material_config(p_order_id uuid,p_material_name text,p_spec text,p_unit text,p_quantity numeric,p_kind text,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean;
begin
 if custom_private.request_role() not in ('owner','factory_manager') or p_request_id is null or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if length(btrim(coalesce(p_material_name,'')))=0 or p_quantity<0 or p_kind not in ('板材','五金','辅料') then raise exception using errcode='22023',message='factory_invalid_material_config'; end if;
 v_dup:=factory_private.claim_request('factory_save_order_material_config',p_request_id,jsonb_build_object('order_id',p_order_id,'name',p_material_name,'spec',p_spec,'unit',p_unit,'quantity',p_quantity,'kind',p_kind,'note',p_note));
 if not v_dup then insert into factory_private.order_material_configs(order_id,material_name,spec,unit,planned_quantity,material_kind,note,created_by)
 values(p_order_id,left(p_material_name,160),left(coalesce(p_spec,''),300),left(coalesce(p_unit,''),32),p_quantity,p_kind,left(coalesce(p_note,''),1000),custom_private.request_uid())
 on conflict(order_id,material_name,spec,material_kind) do update set unit=excluded.unit,planned_quantity=excluded.planned_quantity,note=excluded.note,updated_at=now(); end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_register_order_document(p_order_id uuid,p_kind text,p_file_name text,p_storage_path text,p_mime_type text,p_file_size bigint,p_version text,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean; v_id uuid;
begin
 if custom_private.request_role() not in ('owner','factory_manager') or p_request_id is null or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_kind not in ('图纸','板材单','五金单','合同','变更单','其他资料') or p_file_size is null or p_file_size<=0 or p_file_size>31457280 or not factory_private.order_storage_allowed(p_order_id,p_storage_path,'write') then raise exception using errcode='42501',message='factory_document_forbidden'; end if;
 v_dup:=factory_private.claim_request('factory_register_order_document',p_request_id,jsonb_build_object('order',p_order_id,'kind',p_kind,'path',p_storage_path,'name',p_file_name,'mime',p_mime_type,'size',p_file_size,'version',p_version,'note',p_note));
 if not v_dup then insert into factory_private.order_documents(order_id,document_kind,file_name,storage_path,mime_type,file_size,version_label,note,created_by,request_id)
 values(p_order_id,p_kind,left(p_file_name,255),p_storage_path,p_mime_type,p_file_size,left(coalesce(p_version,''),60),left(coalesce(p_note,''),1000),custom_private.request_uid(),p_request_id) returning id into v_id; end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function factory_private.order_storage_allowed(p_order_id uuid,p_name text,p_action text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare p text[]; v_order uuid;
begin
 if p_name is null or p_name like '%..%' or p_action not in ('read','write') or not factory_private.order_scope_allowed(p_order_id,case when p_action='write' then 'progress' else 'read' end) then return false; end if;
 p:=string_to_array(p_name,'/');
 if array_length(p,1)<>5 or p[1]<>'factory' or p[2] !~* '^[0-9a-f-]{36}$' or p[3] not in ('图纸','板材单','五金单','合同','变更单','其他资料','现场照片') or p[4] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or length(p[5])>180 then return false; end if;
 begin v_order:=p[2]::uuid; exception when others then return false; end;
 if v_order<>p_order_id then return false; end if;
 if p_action='write' then return custom_private.request_role() in ('owner','factory_manager','foreman') and factory_private.order_scope_allowed(p_order_id,'progress'); end if;
 return true;
end $$;
alter function factory_private.order_storage_allowed(uuid,text,text) owner to postgres;
revoke all on function factory_private.order_storage_allowed(uuid,text,text) from public,anon;
grant execute on function factory_private.order_storage_allowed(uuid,text,text) to anju_custom_executor;
grant execute on function factory_private.order_storage_allowed(uuid,text,text) to authenticated;
create or replace function factory_private.storage_path_allowed(p_name text,p_action text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare p text[]; v_order uuid;
begin
 if p_name is null or p_name like '%..%' then return false; end if;
 p:=string_to_array(p_name,'/');
 if array_length(p,1)<>5 or p[1]<>'factory' or p[2] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
 v_order:=p[2]::uuid;
 return factory_private.order_storage_allowed(v_order,p_name,p_action);
exception when others then return false;
end $$;
alter function factory_private.storage_path_allowed(text,text) owner to postgres;
revoke all on function factory_private.storage_path_allowed(text,text) from public,anon;
grant execute on function factory_private.storage_path_allowed(text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('factory-files','factory-files',false,31457280,array['image/jpeg','image/png','image/webp','application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists factory_files_read on storage.objects;
create policy factory_files_read on storage.objects for select to authenticated using(bucket_id='factory-files' and exists(select 1 from factory_private.order_documents d where d.storage_path=name and factory_private.order_scope_allowed(d.order_id,'read')));
drop policy if exists factory_files_insert on storage.objects;
create policy factory_files_insert on storage.objects for insert to authenticated with check(bucket_id='factory-files' and factory_private.storage_path_allowed(name,'write'));

create or replace function api.factory_record_cash_entry(p_order_id uuid,p_kind text,p_date date,p_amount numeric,p_method text,p_counterparty text,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean;
begin
 if custom_private.request_role() not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_kind not in ('收款','付款') or p_amount is null or p_amount<=0 or p_request_id is null then raise exception using errcode='22023',message='factory_cash_invalid'; end if;
 v_dup:=factory_private.claim_request('factory_record_cash_entry',p_request_id,jsonb_build_object('order_id',p_order_id,'kind',p_kind,'date',p_date,'amount',p_amount,'method',p_method,'counterparty',p_counterparty,'note',p_note));
 if not v_dup then insert into factory_private.order_cash_entries(order_id,entry_kind,entry_date,amount,method,counterparty,note,created_by,request_id) values(p_order_id,p_kind,coalesce(p_date,current_date),p_amount,left(coalesce(p_method,''),60),left(coalesce(p_counterparty,''),160),left(coalesce(p_note,''),1000),custom_private.request_uid(),p_request_id); end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_save_outsource_check(p_order_id uuid,p_job_id uuid,p_process text,p_supplier text,p_planned_date date,p_received_date date,p_status text,p_quality_result text,p_actual_cost numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean; v_id uuid; v_old factory_private.outsource_jobs%rowtype; v_cost numeric;
begin
 if custom_private.request_role() not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_request_id is null or length(btrim(coalesce(p_process,'')))=0 or p_status not in ('待送检','加工中','待验货','已验收','返工') or (p_actual_cost is not null and p_actual_cost<0) then raise exception using errcode='22023',message='factory_outsource_invalid'; end if;
 v_dup:=factory_private.claim_request('factory_save_outsource_check',p_request_id,jsonb_build_object('order',p_order_id,'job',p_job_id,'process',p_process,'supplier',p_supplier,'planned',p_planned_date,'received',p_received_date,'status',p_status,'quality',p_quality_result,'cost',p_actual_cost,'note',p_note));
 if not v_dup then
  if p_job_id is null then
   insert into factory_private.outsource_jobs(order_id,process_name,supplier,planned_date,received_date,status,quality_result,actual_cost,note,created_by,request_id) values(p_order_id,left(p_process,160),left(coalesce(p_supplier,''),160),p_planned_date,p_received_date,p_status,left(coalesce(p_quality_result,''),2000),p_actual_cost,left(coalesce(p_note,''),1000),custom_private.request_uid(),p_request_id) returning id into v_id;
   if p_actual_cost>0 and p_status='已验收' then insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,source_id,note,created_by,request_id) values(p_order_id,'外协',p_actual_cost,'outsourcing',v_id,coalesce(p_note,''),custom_private.request_uid(),gen_random_uuid()); end if;
  else
   select * into v_old from factory_private.outsource_jobs where id=p_job_id and order_id=p_order_id for update;
   if not found then raise exception using errcode='42501',message='factory_forbidden'; end if;
   update factory_private.outsource_jobs set process_name=left(p_process,160),supplier=left(coalesce(p_supplier,''),160),planned_date=p_planned_date,received_date=p_received_date,status=p_status,quality_result=left(coalesce(p_quality_result,''),2000),note=left(coalesce(p_note,''),1000),updated_at=now() where id=p_job_id;
   if p_actual_cost is not null and p_status='已验收' and not exists(select 1 from factory_private.order_cost_entries c where c.source_type='outsourcing' and c.source_id=p_job_id) then update factory_private.outsource_jobs set actual_cost=p_actual_cost where id=p_job_id; if p_actual_cost>0 then insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,source_id,note,created_by,request_id) values(p_order_id,'外协',p_actual_cost,'outsourcing',p_job_id,coalesce(p_note,''),custom_private.request_uid(),gen_random_uuid()); end if; end if;
  end if;
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_record_order_site_note(p_order_id uuid,p_kind text,p_content text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean;
begin
 if custom_private.request_role() not in ('owner','factory_manager','foreman') or not factory_private.order_scope_allowed(p_order_id,'progress') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if length(btrim(coalesce(p_content,'')))=0 or p_request_id is null then raise exception using errcode='22023',message='factory_note_invalid'; end if;
 v_dup:=factory_private.claim_request('factory_record_order_site_note',p_request_id,jsonb_build_object('order',p_order_id,'kind',p_kind,'content',p_content));
 if not v_dup then insert into factory_private.order_site_notes(order_id,note_kind,content,created_by,request_id) values(p_order_id,case when p_kind in ('接单要求','特殊工艺','现场备注','验货') then p_kind else '现场备注' end,left(p_content,4000),custom_private.request_uid(),p_request_id); end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_record_attendance_batch(p_work_date date,p_rows jsonb,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean; r jsonb; v_employee uuid;
begin
 if custom_private.request_role() not in ('owner','factory_manager') or p_request_id is null or jsonb_typeof(p_rows)<>'array' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>100 then raise exception using errcode='22023',message='factory_batch_invalid'; end if;
 v_dup:=factory_private.claim_request('factory_record_attendance_batch',p_request_id,jsonb_build_object('date',p_work_date,'rows',p_rows));
 if not v_dup then
  for r in select value from jsonb_array_elements(p_rows) loop
   v_employee:=(r->>'employee_id')::uuid;
   if exists(select 1 from factory_private.attendance a where a.employee_id=v_employee and a.work_date=coalesce(p_work_date,current_date)) then raise exception using errcode='23505',message='factory_attendance_already_exists'; end if;
   perform api.factory_record_attendance(v_employee,coalesce(p_work_date,current_date),coalesce(r->>'job',''),coalesce(r->>'status','出勤'),coalesce((r->>'hours')::numeric,8),coalesce(r->>'work_content',''),coalesce((r->>'piece_quantity')::numeric,0),coalesce((r->>'overtime_hours')::numeric,0),coalesce(r->'allocations','[]'::jsonb),coalesce(r->>'note',''),gen_random_uuid());
  end loop;
 end if;
 return jsonb_build_object('status','ok');
end $$;

-- Explicit function privilege surface; no direct access to the private tables.
do $$ declare r record; begin
 for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname in ('reno_set_customer_assignment_labels','reno_customer_profile_details','reno_save_customer_profile','reno_register_customer_document','reno_update_customer_stage','owner_reno_fixed_costs','factory_assignment_users','owner_assign_factory_work_order','factory_visible_work_orders','factory_order_dossier','factory_save_order_material_config','factory_register_order_document','factory_record_cash_entry','factory_save_outsource_check','factory_record_order_site_note','factory_record_attendance_batch') loop
   execute format('alter function %s owner to anju_custom_executor',r.sig);
   execute format('revoke all on function %s from public,anon',r.sig);
   execute format('grant execute on function %s to authenticated',r.sig);
 end loop;
end $$;

notify pgrst,'reload schema';
commit;
