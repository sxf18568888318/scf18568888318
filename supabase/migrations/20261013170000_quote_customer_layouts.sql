begin;

-- Renovation quote catalog and customer-facing line snapshots. The existing
-- renovation/customer/BOM and financial calculations remain unchanged.
alter table public.reno_quotes
  add column if not exists project_address text not null default '',
  add column if not exists designer_name text not null default '',
  add column if not exists designer_phone text not null default '',
  add column if not exists responsible_person text not null default '',
  add column if not exists validity text not null default '7天';

alter table public.reno_quote_items
  add column if not exists section text not null default '其他/增项',
  add column if not exists workmanship_note text not null default '';
alter table public.reno_order_items
  add column if not exists section text not null default '其他/增项',
  add column if not exists workmanship_note text not null default '';

alter table public.reno_quote_items drop constraint if exists reno_quote_items_unit_check;
alter table public.reno_quote_items add constraint reno_quote_items_unit_check
  check(unit in ('项','个','米','m','m²','㎡','樘','套','批','次'));
alter table public.reno_quote_items drop constraint if exists reno_quote_items_section_check;
alter table public.reno_quote_items add constraint reno_quote_items_section_check
  check(section in ('拆除新建工程','水电暖改造工程','防水工程','木工吊顶工程','泥瓦铺贴工程','墙面油工工程','安装及主材','其他/增项'));
alter table public.reno_order_items drop constraint if exists reno_order_items_section_check;
alter table public.reno_order_items add constraint reno_order_items_section_check
  check(section in ('拆除新建工程','水电暖改造工程','防水工程','木工吊顶工程','泥瓦铺贴工程','墙面油工工程','安装及主材','其他/增项'));

create table if not exists public.reno_quote_item_library (
  id uuid primary key default gen_random_uuid(),
  section text not null check(section in ('拆除新建工程','水电暖改造工程','防水工程','木工吊顶工程','泥瓦铺贴工程','墙面油工工程','安装及主材','其他/增项')),
  item_name text not null check(length(btrim(item_name))>0),
  unit text not null check(unit in ('项','个','米','m','m²','㎡','樘','套','批','次')),
  default_unit_price numeric(14,2) not null default 0 check(default_unit_price>=0),
  workmanship_note text not null default '',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(section,item_name)
);
alter table public.reno_quote_item_library enable row level security;
drop policy if exists reno_quote_item_library_executor on public.reno_quote_item_library;
create policy reno_quote_item_library_executor on public.reno_quote_item_library
  for all to anju_custom_executor using (true) with check (true);
revoke all on public.reno_quote_item_library from public,anon,authenticated;
grant select,insert,update,delete on public.reno_quote_item_library to anju_custom_executor;

insert into public.reno_quote_item_library(section,item_name,unit,default_unit_price,workmanship_note,sort_order,created_by,updated_by)
select x.section,x.item_name,x.unit,x.price,x.note,x.sort_order,u.id,u.id
from (values
 ('拆除新建工程','新建墙体','m²',250::numeric,'砌筑方式、挂网及找平范围按现场确认',10),
 ('水电暖改造工程','电路改造','项',3000::numeric,'半改参考价；点位、线径及开槽修补范围按现场确认',10),
 ('水电暖改造工程','水路改造','项',3500::numeric,'参考价 3000–4500；管材品牌、走向及打压验收按合同确认',20),
 ('防水工程','卫生间防水','m²',45::numeric,'科顺 / 雨虹等品牌，墙刚地柔及闭水验收按合同确认',10),
 ('木工吊顶工程','无主灯悬浮吊顶','m²',150::numeric,'龙骨、石膏板及灯槽工艺按现场交底',10),
 ('木工吊顶工程','双层顶带线','m',40::numeric,'层级、灯槽和收边工艺按图纸确认',20)
) as x(section,item_name,unit,price,note,sort_order)
cross join lateral (select id from auth.users where raw_app_meta_data->>'role'='owner' order by created_at limit 1) u
where not exists(select 1 from public.reno_quote_item_library l where l.section=x.section and l.item_name=x.item_name);

create or replace function custom_private.read_reno_quote_item_library()
returns table(id uuid,section text,item_name text,unit text,default_unit_price numeric,workmanship_note text,sort_order integer,is_active boolean)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select l.id,l.section,l.item_name,l.unit,l.default_unit_price,l.workmanship_note,l.sort_order,l.is_active
 from public.reno_quote_item_library l where l.is_active or custom_private.request_role()='owner'
 order by l.section,l.sort_order,l.item_name;
end $$;
alter function custom_private.read_reno_quote_item_library() owner to anju_custom_executor;
revoke all on function custom_private.read_reno_quote_item_library() from public,anon;
grant execute on function custom_private.read_reno_quote_item_library() to authenticated;
create or replace view api.reno_quote_item_library with (security_invoker=false)
as select * from custom_private.read_reno_quote_item_library();
alter view api.reno_quote_item_library owner to anju_custom_executor;
revoke all on api.reno_quote_item_library from public,anon;
grant select on api.reno_quote_item_library to authenticated;

create or replace function api.reno_save_quote_item_library(
 p_id uuid,p_section text,p_item_name text,p_unit text,p_default_unit_price numeric,p_workmanship_note text,p_sort_order integer,p_is_active boolean,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'reno_quote_library_save');if v_existing is not null then return v_existing;end if;
 if p_section not in ('拆除新建工程','水电暖改造工程','防水工程','木工吊顶工程','泥瓦铺贴工程','墙面油工工程','安装及主材','其他/增项')
 or p_unit not in ('项','个','米','m','m²','㎡','樘','套','批','次') or length(btrim(coalesce(p_item_name,'')))=0 or coalesce(p_default_unit_price,-1)<0 then
  raise exception using errcode='22023',message='reno_quote_library_invalid';
 end if;
 if p_id is null then
  insert into public.reno_quote_item_library(section,item_name,unit,default_unit_price,workmanship_note,sort_order,is_active,created_by,updated_by)
  values(p_section,btrim(p_item_name),p_unit,p_default_unit_price,coalesce(p_workmanship_note,''),coalesce(p_sort_order,0),coalesce(p_is_active,true),custom_private.request_uid(),custom_private.request_uid()) returning id into v_id;
 else
  update public.reno_quote_item_library set section=p_section,item_name=btrim(p_item_name),unit=p_unit,default_unit_price=p_default_unit_price,
   workmanship_note=coalesce(p_workmanship_note,''),sort_order=coalesce(p_sort_order,0),is_active=coalesce(p_is_active,true),updated_by=custom_private.request_uid(),updated_at=now()
  where id=p_id returning id into v_id;
  if v_id is null then raise exception using errcode='42501',message='reno_quote_library_forbidden';end if;
 end if;
 v_response:=jsonb_build_object('status',case when p_id is null then 'created' else 'updated' end);
 perform custom_private.reno_store_receipt(p_request_id,'reno_quote_library_save',coalesce(v_id,p_id),v_response);return v_response;
end $$;

create or replace function api.reno_create_quote_v2(
 p_customer_id uuid,p_quote_no text,p_version integer,p_quote_date date,p_design_fee numeric,p_tax numeric,p_discount numeric,p_header jsonb,p_items jsonb,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=custom_private.request_uid();v_designer uuid;v_quote uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'reno_quote_create_v2');if v_existing is not null then return v_existing;end if;
 if not custom_private.reno_customer_allowed(p_customer_id) then raise exception using errcode='42501',message='reno_customer_forbidden';end if;
 if length(btrim(coalesce(p_quote_no,'')))=0 or coalesce(p_version,0)<1 or coalesce(p_design_fee,0)<0 or coalesce(p_tax,0)<0 or coalesce(p_discount,0)<0 or jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then
  raise exception using errcode='22023',message='reno_quote_invalid';end if;
 select coalesce(c.designer_id,c.owner_id) into v_designer from public.customers c where c.id=p_customer_id;
 insert into public.reno_quotes(customer_id,quote_no,version,designer_id,quote_date,design_fee,tax,discount,project_address,designer_name,designer_phone,responsible_person,validity,created_by)
 values(p_customer_id,p_quote_no,p_version, v_designer,coalesce(p_quote_date,current_date),coalesce(p_design_fee,0),coalesce(p_tax,0),coalesce(p_discount,0),
  coalesce(p_header->>'project_address',''),coalesce(p_header->>'designer_name',''),coalesce(p_header->>'designer_phone',''),coalesce(p_header->>'responsible_person',''),coalesce(nullif(p_header->>'validity',''),'7天'),v_actor) returning id into v_quote;
 insert into public.reno_quote_items(quote_id,line_no,space,section,category,item_name,spec,unit,quantity,unit_price,in_package,note,workmanship_note)
 select v_quote,x.line_no,coalesce(nullif(x.space,''),'其他'),x.section,'其他',x.item_name,coalesce(x.spec,''),x.unit,x.quantity,x.unit_price,false,
  coalesce(x.workmanship_note,''),coalesce(x.workmanship_note,'')
 from jsonb_to_recordset(coalesce(p_items,'[]'::jsonb)) as x(line_no integer,space text,section text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,workmanship_note text)
 order by x.line_no;
 if not exists(select 1 from public.reno_quote_items i where i.quote_id=v_quote) then raise exception using errcode='22023',message='reno_quote_items_required';end if;
 v_response:=jsonb_build_object('status','created','id',v_quote);perform custom_private.reno_store_receipt(p_request_id,'reno_quote_create_v2',v_quote,v_response);return v_response;
end $$;

create or replace function custom_private.read_reno_quote_item_details()
returns table(id uuid,quote_id uuid,line_no integer,space text,section text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,amount numeric,in_package boolean,note text,workmanship_note text)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select i.id,i.quote_id,i.line_no,i.space,i.section,i.item_name,i.spec,i.unit,i.quantity,i.unit_price,i.amount,i.in_package,i.note,i.workmanship_note
 from public.reno_quote_items i where custom_private.reno_quote_allowed(i.quote_id) order by i.quote_id,i.line_no;
end $$;
alter function custom_private.read_reno_quote_item_details() owner to anju_custom_executor;
revoke all on function custom_private.read_reno_quote_item_details() from public,anon;
grant execute on function custom_private.read_reno_quote_item_details() to authenticated;
create or replace view api.reno_quote_item_details with (security_invoker=false) as select * from custom_private.read_reno_quote_item_details();
alter view api.reno_quote_item_details owner to anju_custom_executor;
revoke all on api.reno_quote_item_details from public,anon;
grant select on api.reno_quote_item_details to authenticated;

create or replace function api.reno_sign_quote(p_quote_id uuid,p_foreman_id uuid,p_signed_at timestamptz,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_quote public.reno_quotes%rowtype;v_customer public.customers%rowtype;v_order uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'quote_sign');if v_existing is not null then return v_existing;end if;
 select * into v_quote from public.reno_quotes q where q.id=p_quote_id and custom_private.reno_quote_allowed(q.id) for update;
 if not found or v_quote.status<>'已发客户' then raise exception using errcode='42501',message='reno_quote_forbidden_or_not_sent';end if;
 select * into v_customer from public.customers c where c.id=v_quote.customer_id;
 if p_foreman_id is not null and not exists(select 1 from auth.users u where u.id=p_foreman_id and u.raw_app_meta_data->>'role'='foreman') then raise exception using errcode='22023',message='reno_foreman_invalid';end if;
 insert into public.reno_orders(customer_id,quote_id,contract_amount,business_status,designer_id,foreman_id,signed_at,current_stage,status,created_by,request_id)
 values(v_quote.customer_id,v_quote.id,v_quote.total_amount,'已签约',v_quote.designer_id,coalesce(p_foreman_id,v_customer.foreman_id),coalesce(p_signed_at,now()),'开工交底','待开工',custom_private.request_uid(),p_request_id) returning id into v_order;
 insert into public.reno_order_items(order_id,source_item_id,line_no,space,category,item_name,spec,unit,quantity,unit_price,in_package,note,section,workmanship_note)
 select v_order,i.id,i.line_no,i.space,i.category,i.item_name,i.spec,i.unit,i.quantity,i.unit_price,i.in_package,i.note,i.section,i.workmanship_note from public.reno_quote_items i where i.quote_id=v_quote.id order by i.line_no;
 insert into public.reno_order_stages(order_id,seq,name,foreman_id) select v_order,t.seq,t.name,coalesce(p_foreman_id,v_customer.foreman_id) from public.reno_stage_templates t where t.is_active order by t.seq;
 update public.reno_quotes set status='已签约',signed_at=coalesce(p_signed_at,now()) where id=v_quote.id;
 update public.customers set business_status='已签约',stage='开工交底',foreman_id=coalesce(p_foreman_id,v_customer.foreman_id) where id=v_quote.customer_id;
 v_response:=jsonb_build_object('status','created','order_id',v_order);perform custom_private.reno_store_receipt(p_request_id,'quote_sign',v_order,v_response);return v_response;
end $$;

do $$ declare f record; begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname in ('reno_save_quote_item_library','reno_create_quote_v2') loop
  execute format('alter function %s owner to anju_custom_executor',f.sig);
  execute format('revoke all on function %s from public,anon',f.sig);
  execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;
alter function api.reno_sign_quote(uuid,uuid,timestamptz,uuid) owner to anju_custom_executor;
revoke all on function api.reno_sign_quote(uuid,uuid,timestamptz,uuid) from public,anon;
grant execute on function api.reno_sign_quote(uuid,uuid,timestamptz,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
