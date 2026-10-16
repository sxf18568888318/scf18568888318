begin;

-- Normalize renovation quote sections to trades and make the quote line's
-- legacy `space` column carry the same trade label for existing clients.
alter table public.reno_quote_items drop constraint if exists reno_quote_items_section_check;
alter table public.reno_order_items drop constraint if exists reno_order_items_section_check;

alter table public.reno_quote_items add constraint reno_quote_items_section_check
  check(section in ('拆除新建','水电暖改造','防水','木工吊顶','泥瓦铺贴','墙面油工','安装主材','其他增项','拆除新建工程','水电暖改造工程','防水工程','木工吊顶工程','泥瓦铺贴工程','墙面油工工程','安装及主材','其他/增项'));
alter table public.reno_quote_items drop constraint if exists reno_quote_items_space_check;
alter table public.reno_quote_items add constraint reno_quote_items_space_check
  check(space in ('拆除新建','水电暖改造','防水','木工吊顶','泥瓦铺贴','墙面油工','安装主材','其他增项','全屋/基础工程','客厅','餐厅','主卧','次卧','儿童房','厨房','主卫','次卫','阳台','水电','其他'));
alter table public.reno_order_items add constraint reno_order_items_section_check
  check(section in ('拆除新建','水电暖改造','防水','木工吊顶','泥瓦铺贴','墙面油工','安装主材','其他增项','拆除新建工程','水电暖改造工程','防水工程','木工吊顶工程','泥瓦铺贴工程','墙面油工工程','安装及主材','其他/增项'));

alter table public.reno_quote_item_library drop constraint if exists reno_quote_item_library_section_check;
alter table public.reno_quote_item_library drop constraint if exists reno_quote_item_library_unit_check;
alter table public.reno_quote_item_library add constraint reno_quote_item_library_unit_check
  check(unit in ('m²','m','项','套','个','樘','米','㎡','批','次'));

update public.reno_quote_item_library
set section=case section
  when '拆除新建工程' then '拆除新建'
  when '水电暖改造工程' then '水电暖改造'
  when '防水工程' then '防水'
  when '木工吊顶工程' then '木工吊顶'
  when '泥瓦铺贴工程' then '泥瓦铺贴'
  when '墙面油工工程' then '墙面油工'
  when '安装及主材' then '安装主材'
  when '其他/增项' then '其他增项'
  else section end;
update public.reno_quote_item_library
set item_name='客餐厅无主灯悬浮吊顶'
where item_name='无主灯悬浮吊顶' and section='木工吊顶';
alter table public.reno_quote_item_library add constraint reno_quote_item_library_section_check
  check(section in ('拆除新建','水电暖改造','防水','木工吊顶','泥瓦铺贴','墙面油工','安装主材','其他增项'));

insert into public.reno_quote_item_library(section,item_name,unit,default_unit_price,workmanship_note,sort_order,created_by,updated_by)
select x.section,x.item_name,x.unit,x.price,x.note,x.sort_order,u.id,u.id
from (values
 ('电路改造'::text,'水电暖改造'::text,'项'::text,3000::numeric,'电路半改横平竖直，国标线顶面布线，强弱电交接锡纸包裹'::text,10),
 ('水路改造','水电暖改造','项',3000::numeric,'参考价 3000～4500；水路全改，25/20 管，金牛 / 伟星三层抗菌，不含前置过滤',20),
 ('厨房防水','防水','m²',45::numeric,'科顺 / 雨虹，墙刚地柔',10),
 ('卫生间防水','防水','m²',45::numeric,'淋浴区 1.8 米，水盆区 1 米',20),
 ('客餐厅无主灯悬浮吊顶','木工吊顶','m²',150::numeric,'圣戈班 0.95 石膏板 + 木龙骨',10),
 ('双层顶带线','木工吊顶','m',40::numeric,'',20),
 ('新建墙体','拆除新建','m²',250::numeric,'红砖 / 青砖 + 过梁，植入钢筋挂网',10),
 ('贴砖工费','泥瓦铺贴','m²',25::numeric,'',10),
 ('沙子水泥','泥瓦铺贴','m²',12::numeric,'',20),
 ('美缝','其他增项','项',1700::numeric,'',10),
 ('批墙乳胶漆','墙面油工','m²',27::numeric,'立邦 / 多乐士，腻子',10)
) as x(item_name,section,unit,price,note,sort_order)
cross join lateral (select id from auth.users where raw_app_meta_data->>'role'='owner' order by created_at limit 1) u
on conflict(section,item_name) do update set
  unit=excluded.unit,
  default_unit_price=excluded.default_unit_price,
  workmanship_note=excluded.workmanship_note,
  sort_order=excluded.sort_order,
  is_active=true,
  updated_by=excluded.updated_by,
  updated_at=now();

create or replace function api.reno_save_quote_item_library(
 p_id uuid,p_section text,p_item_name text,p_unit text,p_default_unit_price numeric,p_workmanship_note text,p_sort_order integer,p_is_active boolean,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'reno_quote_library_save');if v_existing is not null then return v_existing;end if;
 if p_section not in ('拆除新建','水电暖改造','防水','木工吊顶','泥瓦铺贴','墙面油工','安装主材','其他增项')
 or p_unit not in ('m²','m','项','套','个','樘','米','㎡','批','次') or length(btrim(coalesce(p_item_name,'')))=0 or coalesce(p_default_unit_price,-1)<0 then
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
 if exists(select 1 from jsonb_to_recordset(coalesce(p_items,'[]'::jsonb)) as x(section text) where x.section not in ('拆除新建','水电暖改造','防水','木工吊顶','泥瓦铺贴','墙面油工','安装主材','其他增项')) then
  raise exception using errcode='22023',message='reno_quote_section_invalid';
 end if;
 select coalesce(c.designer_id,c.owner_id) into v_designer from public.customers c where c.id=p_customer_id;
 insert into public.reno_quotes(customer_id,quote_no,version,designer_id,quote_date,design_fee,tax,discount,project_address,designer_name,designer_phone,responsible_person,validity,created_by)
 values(p_customer_id,p_quote_no,p_version,v_designer,coalesce(p_quote_date,current_date),coalesce(p_design_fee,0),coalesce(p_tax,0),coalesce(p_discount,0),
  coalesce(p_header->>'project_address',''),coalesce(p_header->>'designer_name',''),coalesce(p_header->>'designer_phone',''),coalesce(p_header->>'responsible_person',''),coalesce(nullif(p_header->>'validity',''),'7天'),v_actor) returning id into v_quote;
 insert into public.reno_quote_items(quote_id,line_no,space,section,category,item_name,spec,unit,quantity,unit_price,in_package,note,workmanship_note)
 select v_quote,x.line_no,x.section,x.section,'其他',x.item_name,coalesce(x.spec,''),x.unit,x.quantity,x.unit_price,false,coalesce(x.workmanship_note,''),coalesce(x.workmanship_note,'')
 from jsonb_to_recordset(coalesce(p_items,'[]'::jsonb)) as x(line_no integer,space text,section text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,workmanship_note text)
 order by x.line_no;
 if not exists(select 1 from public.reno_quote_items i where i.quote_id=v_quote) then raise exception using errcode='22023',message='reno_quote_items_required';end if;
 v_response:=jsonb_build_object('status','created','id',v_quote);perform custom_private.reno_store_receipt(p_request_id,'reno_quote_create_v2',v_quote,v_response);return v_response;
end $$;

alter function api.reno_save_quote_item_library(uuid,text,text,text,numeric,text,integer,boolean,uuid) owner to anju_custom_executor;
revoke all on function api.reno_save_quote_item_library(uuid,text,text,text,numeric,text,integer,boolean,uuid) from public,anon;
grant execute on function api.reno_save_quote_item_library(uuid,text,text,text,numeric,text,integer,boolean,uuid) to authenticated;
alter function api.reno_create_quote_v2(uuid,text,integer,date,numeric,numeric,numeric,jsonb,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.reno_create_quote_v2(uuid,text,integer,date,numeric,numeric,numeric,jsonb,jsonb,uuid) from public,anon;
grant execute on function api.reno_create_quote_v2(uuid,text,integer,date,numeric,numeric,numeric,jsonb,jsonb,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
