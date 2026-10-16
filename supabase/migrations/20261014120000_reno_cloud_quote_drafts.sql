begin;

-- Persist measured dimensions as quote source data; keep existing line totals
-- database-generated from quantity * unit_price.
alter table public.reno_quote_items
  add column if not exists pricing_mode text not null default '按单位',
  add column if not exists width_mm numeric,
  add column if not exists height_mm numeric,
  add column if not exists length_m numeric;

alter table public.reno_quote_items drop constraint if exists reno_quote_items_unit_check;
alter table public.reno_quote_items add constraint reno_quote_items_unit_check
  check (unit = any(array['项','个','米','m','m²','㎡','樘','套','批','次','投影','延米','平方']::text[]));
alter table public.reno_quote_items drop constraint if exists reno_quote_items_pricing_mode_check;
alter table public.reno_quote_items add constraint reno_quote_items_pricing_mode_check
  check (pricing_mode = any(array['按单位','投影','延米','平方']::text[]));
alter table public.reno_quote_items drop constraint if exists reno_quote_items_dimensions_nonnegative;
alter table public.reno_quote_items add constraint reno_quote_items_dimensions_nonnegative
  check (coalesce(width_mm,0) >= 0 and coalesce(height_mm,0) >= 0 and coalesce(length_m,0) >= 0);

create or replace function api.reno_save_quote_draft(
 p_quote_id uuid,
 p_customer_id uuid,
 p_quote_no text,
 p_version integer,
 p_quote_date date,
 p_design_fee numeric,
 p_tax numeric,
 p_discount numeric,
 p_header jsonb,
 p_items jsonb,
 p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid := custom_private.request_uid();
 v_designer uuid;
 v_quote_id uuid := p_quote_id;
 v_quote public.reno_quotes%rowtype;
 v_response jsonb;
 v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);
 v_existing := custom_private.reno_request_replay(p_request_id,'reno_quote_draft_save');
 if v_existing is not null then return v_existing; end if;
 if not custom_private.reno_customer_allowed(p_customer_id) then
  raise exception using errcode='42501',message='reno_customer_forbidden';
 end if;
 if length(btrim(coalesce(p_quote_no,'')))=0 or coalesce(p_version,0)<1
   or coalesce(p_design_fee,0)<0 or coalesce(p_tax,0)<0 or coalesce(p_discount,0)<0
   or jsonb_typeof(coalesce(p_header,'{}'::jsonb))<>'object'
   or jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then
  raise exception using errcode='22023',message='reno_quote_invalid';
 end if;
 if exists(
  select 1 from jsonb_to_recordset(coalesce(p_items,'[]'::jsonb)) as x(
   section text,unit text,quantity numeric,unit_price numeric,pricing_mode text,width_mm numeric,height_mm numeric,length_m numeric
  )
  where x.section not in ('拆除新建','水电暖改造','防水','木工吊顶','泥瓦铺贴','墙面油工','安装主材','其他增项')
    or x.unit not in ('项','个','米','m','m²','㎡','樘','套','批','次','投影','延米','平方')
    or coalesce(x.quantity,-1)<0 or coalesce(x.unit_price,-1)<0
    or coalesce(x.pricing_mode,'按单位') not in ('按单位','投影','延米','平方')
    or coalesce(x.width_mm,0)<0 or coalesce(x.height_mm,0)<0 or coalesce(x.length_m,0)<0
    -- Drafts are autosaved while the designer is midway through dimensions.
    -- Missing dimensions yield quantity 0; completing the fields recalculates
    -- on the next save. No partial draft can be signed into an order directly.
 ) then
  raise exception using errcode='22023',message='reno_quote_item_invalid';
 end if;
 select coalesce(c.designer_id,c.owner_id) into v_designer from public.customers c where c.id=p_customer_id;
 if v_quote_id is null then
  insert into public.reno_quotes(customer_id,quote_no,version,status,designer_id,quote_date,design_fee,tax,discount,project_address,designer_name,designer_phone,responsible_person,validity,created_by)
  values(p_customer_id,btrim(p_quote_no),p_version,'草稿',v_designer,coalesce(p_quote_date,current_date),coalesce(p_design_fee,0),coalesce(p_tax,0),coalesce(p_discount,0),
    coalesce(p_header->>'project_address',''),coalesce(p_header->>'designer_name',''),coalesce(p_header->>'designer_phone',''),coalesce(p_header->>'responsible_person',''),coalesce(nullif(p_header->>'validity',''),'30天'),v_actor)
  returning id into v_quote_id;
 else
  select * into v_quote from public.reno_quotes q where q.id=v_quote_id for update;
  if not found or v_quote.customer_id<>p_customer_id or v_quote.status<>'草稿' or not custom_private.reno_quote_allowed(v_quote_id) then
   raise exception using errcode='42501',message='reno_quote_locked_or_forbidden';
  end if;
  update public.reno_quotes set quote_no=btrim(p_quote_no),version=p_version,quote_date=coalesce(p_quote_date,current_date),
   design_fee=coalesce(p_design_fee,0),tax=coalesce(p_tax,0),discount=coalesce(p_discount,0),
   project_address=coalesce(p_header->>'project_address',''),designer_name=coalesce(p_header->>'designer_name',''),
   designer_phone=coalesce(p_header->>'designer_phone',''),responsible_person=coalesce(p_header->>'responsible_person',''),
   validity=coalesce(nullif(p_header->>'validity',''),'30天')
  where id=v_quote_id;
  delete from public.reno_quote_items where quote_id=v_quote_id;
 end if;

 insert into public.reno_quote_items(quote_id,line_no,space,section,category,item_name,spec,unit,quantity,unit_price,in_package,note,workmanship_note,pricing_mode,width_mm,height_mm,length_m)
 select v_quote_id,x.line_no,x.section,x.section,'其他',btrim(x.item_name),coalesce(x.spec,''),x.unit,
  case coalesce(x.pricing_mode,'按单位')
   when '投影' then round(coalesce(x.width_mm,0)*coalesce(x.height_mm,0)/1000000,4)
   when '平方' then round(coalesce(x.width_mm,0)*coalesce(x.height_mm,0)/1000000,4)
   when '延米' then round(coalesce(x.length_m,coalesce(x.width_mm,0)/1000),4)
   else coalesce(x.quantity,0)
  end,
  coalesce(x.unit_price,0),false,coalesce(x.workmanship_note,''),coalesce(x.workmanship_note,''),coalesce(x.pricing_mode,'按单位'),x.width_mm,x.height_mm,x.length_m
 from jsonb_to_recordset(coalesce(p_items,'[]'::jsonb)) as x(
  line_no integer,space text,section text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,
  workmanship_note text,pricing_mode text,width_mm numeric,height_mm numeric,length_m numeric
 )
 where length(btrim(coalesce(x.item_name,'')))>0
 order by x.line_no;

 v_response:=jsonb_build_object('status','saved','id',v_quote_id);
 perform custom_private.reno_store_receipt(p_request_id,'reno_quote_draft_save',v_quote_id,v_response);
 return v_response;
end $$;

alter function api.reno_save_quote_draft(uuid,uuid,text,integer,date,numeric,numeric,numeric,jsonb,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.reno_save_quote_draft(uuid,uuid,text,integer,date,numeric,numeric,numeric,jsonb,jsonb,uuid) from public,anon;
grant execute on function api.reno_save_quote_draft(uuid,uuid,text,integer,date,numeric,numeric,numeric,jsonb,jsonb,uuid) to authenticated;

create or replace function custom_private.read_reno_quote_draft_details()
returns table(id uuid,quote_id uuid,line_no integer,space text,section text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,amount numeric,in_package boolean,note text,workmanship_note text,pricing_mode text,width_mm numeric,height_mm numeric,length_m numeric)
language plpgsql stable security definer set search_path=''
as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select i.id,i.quote_id,i.line_no,i.space,i.section,i.item_name,i.spec,i.unit,i.quantity,i.unit_price,i.amount,i.in_package,i.note,i.workmanship_note,i.pricing_mode,i.width_mm,i.height_mm,i.length_m
 from public.reno_quote_items i where custom_private.reno_quote_allowed(i.quote_id) order by i.quote_id,i.line_no;
end $$;
alter function custom_private.read_reno_quote_draft_details() owner to anju_custom_executor;
revoke all on function custom_private.read_reno_quote_draft_details() from public,anon;
grant execute on function custom_private.read_reno_quote_draft_details() to authenticated;
create or replace view api.reno_quote_draft_details with (security_invoker=false) as select * from custom_private.read_reno_quote_draft_details();
alter view api.reno_quote_draft_details owner to anju_custom_executor;
revoke all on api.reno_quote_draft_details from public,anon;
grant select on api.reno_quote_draft_details to authenticated;

notify pgrst,'reload schema';
commit;
