-- Persist full custom quote-workbench drafts in Supabase. Draft totals are
-- deliberately stored only in the draft payload; quotes.amount remains zero
-- until the existing BOM booking workflow computes a booked amount.
begin;

alter table public.quotes
  add column if not exists custom_draft_payload jsonb;

create or replace function custom_private.save_quote_draft(
  p_quote_id uuid,
  p_customer_id uuid,
  p_title text,
  p_payload jsonb,
  p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := custom_private.request_uid();
  v_role text := custom_private.request_role();
  v_quote_id uuid := coalesce(p_quote_id, gen_random_uuid());
  v_receipt uuid;
  v_quote public.quotes%rowtype;
  v_row jsonb;
begin
  perform custom_private.require_roles(array['owner','designer']);
  if v_uid is null or p_request_id is null then
    raise exception using errcode='42501', message='custom_quote_forbidden';
  end if;
  if p_customer_id is null or not custom_private.customer_allowed(p_customer_id) then
    raise exception using errcode='42501', message='custom_customer_forbidden';
  end if;
  if coalesce(length(p_title),0) not between 1 and 160
     or jsonb_typeof(p_payload)<>'object'
     or octet_length(p_payload::text)>500000
     or p_payload->>'customerId' is distinct from p_customer_id::text
     or jsonb_typeof(coalesce(p_payload->'rows','[]'::jsonb))<>'array' then
    raise exception using errcode='22023', message='custom_quote_draft_invalid';
  end if;
  perform custom_private.validate_keys(p_payload,array['type','customerId','customer','address','contact','phone','owner','date','validity','requirements','exclusions','customerType','channel','payments','channelTerms','discount','deliveryFee','installFee','projectedPrice','linearPrice','factoryOrderNo','measurementDate','deliveryDate','clientProjectedArea','clientDoorArea','orderNote','rooms','activeRoom','baseMaterial','doorMaterial','rows','documents','subtotal','amount','savedAt']);
  if jsonb_typeof(p_payload->'baseMaterial')='object' then perform custom_private.validate_keys(p_payload->'baseMaterial',array['brand','substrate','thickness','color','door','finish','grade','model','spec']); end if;
  if jsonb_typeof(p_payload->'doorMaterial')='object' then perform custom_private.validate_keys(p_payload->'doorMaterial',array['brand','substrate','thickness','color','door','finish','grade','model','spec']); end if;
  for v_row in select value from jsonb_array_elements(coalesce(p_payload->'rows','[]'::jsonb)) loop
    perform custom_private.validate_keys(v_row,array['name','category','mode','unit','qty','quantity','width','height','depth','deduct','price','amount','room','spec','remark','note','included','charge','includedIn','expandedArea','directArea','measureVersion','measureSource','material','standalonePrice','upgradePrice']);
    if jsonb_typeof(v_row->'material')='object' then perform custom_private.validate_keys(v_row->'material',array['brand','substrate','thickness','color','door','finish','grade','model','spec']); end if;
  end loop;
  if not pg_try_advisory_xact_lock(hashtextextended(p_request_id::text,0)) then
    raise exception using errcode='40001', message='custom_retry_request';
  end if;
  select entity_id into v_receipt from custom_private.write_receipts
    where request_id=p_request_id and actor_id=v_uid and operation='quote_draft';
  if found then return jsonb_build_object('id',v_receipt,'status','existing'); end if;

  if p_quote_id is null then
    insert into public.quotes(id,customer_id,business_line,title,amount,status,created_by)
      values(v_quote_id,p_customer_id,'custom',p_title,0,'draft',v_uid);
  else
    select * into v_quote from public.quotes where id=p_quote_id and business_line='custom' for update;
    if not found or v_quote.status<>'draft'
       or not custom_private.customer_allowed(v_quote.customer_id)
       or v_quote.created_by<>v_uid and v_role<>'owner' then
      raise exception using errcode='42501', message='custom_quote_forbidden';
    end if;
    if v_quote.customer_id<>p_customer_id then
      raise exception using errcode='42501', message='custom_quote_customer_locked';
    end if;
    update public.quotes set title=p_title, amount=0, custom_draft_payload=p_payload
      where id=v_quote.id;
  end if;
  if p_quote_id is null then
    update public.quotes set custom_draft_payload=p_payload where id=v_quote_id;
  end if;
  insert into custom_private.write_receipts(request_id,actor_id,entity_id,operation)
    values(p_request_id,v_uid,v_quote_id,'quote_draft');
  return jsonb_build_object('id',v_quote_id,'status','saved');
end
$$;

create or replace function api.custom_save_quote_draft(
  p_quote_id uuid, p_customer_id uuid, p_title text, p_payload jsonb, p_request_id uuid
) returns jsonb language sql security invoker set search_path=''
as $$ select custom_private.save_quote_draft(p_quote_id,p_customer_id,p_title,p_payload,p_request_id) $$;

create or replace function custom_private.save_customer(
  p_customer_id uuid, p_data jsonb, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid := custom_private.request_uid();
  v_role text := custom_private.request_role();
  v_id uuid := coalesce(p_customer_id,gen_random_uuid());
  v_receipt uuid;
  v_customer public.customers%rowtype;
begin
  perform custom_private.require_roles(array['owner','designer']);
  if v_uid is null or p_request_id is null or jsonb_typeof(p_data)<>'object' then
    raise exception using errcode='22023', message='custom_customer_invalid';
  end if;
  if exists(select 1 from jsonb_object_keys(p_data) as j(key) where j.key not in
    ('name','phone','community','unit','layout','area_m2','source','status','next_followup_at','last_followup_text','business_status','business_type','owner_id','designer_id','foreman_id')) then
    raise exception using errcode='22023', message='custom_customer_invalid';
  end if;
  if length(trim(coalesce(p_data->>'name','')))=0 or length(p_data::text)>10000 then
    raise exception using errcode='22023', message='custom_customer_invalid';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended(p_request_id::text,0)) then
    raise exception using errcode='40001', message='custom_retry_request';
  end if;
  select entity_id into v_receipt from custom_private.write_receipts
    where request_id=p_request_id and actor_id=v_uid and operation='customer';
  if found then return jsonb_build_object('id',v_receipt,'status','existing'); end if;
  if p_customer_id is null then
    insert into public.customers(id,business_line,name,phone,community,owner_id,status,unit,layout,area_m2,source,designer_id,next_followup_at,last_followup_text,business_status,business_type)
    values(v_id,'custom',trim(p_data->>'name'),coalesce(p_data->>'phone',''),coalesce(p_data->>'community',''),v_uid,coalesce(p_data->>'status','lead'),coalesce(p_data->>'unit',''),coalesce(p_data->>'layout',''),nullif(p_data->>'area_m2','')::numeric,coalesce(p_data->>'source',''),v_uid,nullif(p_data->>'next_followup_at','')::date,coalesce(p_data->>'last_followup_text',''),coalesce(p_data->>'business_status','沟通中'),coalesce(p_data->>'business_type','全屋定制'));
  else
    select * into v_customer from public.customers where id=p_customer_id and business_line='custom' for update;
    if not found or not custom_private.customer_allowed(p_customer_id) then
      raise exception using errcode='42501', message='custom_customer_forbidden';
    end if;
    update public.customers set name=trim(p_data->>'name'),phone=coalesce(p_data->>'phone',''),community=coalesce(p_data->>'community',''),unit=coalesce(p_data->>'unit',''),layout=coalesce(p_data->>'layout',''),area_m2=nullif(p_data->>'area_m2','')::numeric,source=coalesce(p_data->>'source',''),status=coalesce(p_data->>'status',status),next_followup_at=nullif(p_data->>'next_followup_at','')::date,last_followup_text=coalesce(p_data->>'last_followup_text',''),business_status=coalesce(p_data->>'business_status',business_status),business_type=coalesce(p_data->>'business_type',business_type)
    where id=p_customer_id;
  end if;
  insert into custom_private.write_receipts(request_id,actor_id,entity_id,operation)
    values(p_request_id,v_uid,v_id,'customer');
  return jsonb_build_object('id',v_id,'status','saved');
end
$$;

create or replace function api.custom_save_customer(p_customer_id uuid,p_data jsonb,p_request_id uuid)
returns jsonb language sql security invoker set search_path=''
as $$ select custom_private.save_customer(p_customer_id,p_data,p_request_id) $$;

create or replace view api.custom_quote_draft_details as
  select q.id, q.customer_id, q.title, q.status, q.created_by, q.created_at,
         q.custom_draft_payload as draft_payload
    from public.quotes q
   where q.business_line='custom' and q.status='draft'
     and q.custom_draft_payload is not null
     and custom_private.customer_allowed(q.customer_id);

alter function custom_private.save_quote_draft(uuid,uuid,text,jsonb,uuid) owner to anju_custom_executor;
revoke all on function custom_private.save_quote_draft(uuid,uuid,text,jsonb,uuid) from public,anon;
grant execute on function custom_private.save_quote_draft(uuid,uuid,text,jsonb,uuid) to authenticated;
alter function api.custom_save_quote_draft(uuid,uuid,text,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.custom_save_quote_draft(uuid,uuid,text,jsonb,uuid) from public,anon;
grant execute on function api.custom_save_quote_draft(uuid,uuid,text,jsonb,uuid) to authenticated;
alter function custom_private.save_customer(uuid,jsonb,uuid) owner to anju_custom_executor;
revoke all on function custom_private.save_customer(uuid,jsonb,uuid) from public,anon;
grant execute on function custom_private.save_customer(uuid,jsonb,uuid) to authenticated;
alter function api.custom_save_customer(uuid,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.custom_save_customer(uuid,jsonb,uuid) from public,anon;
grant execute on function api.custom_save_customer(uuid,jsonb,uuid) to authenticated;
alter view api.custom_quote_draft_details owner to anju_custom_executor;
grant select on api.custom_quote_draft_details to authenticated;
grant select on public.quotes to anju_custom_executor;
notify pgrst,'reload schema';
commit;
