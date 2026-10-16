-- Avoid a transient negative generated total when inserting a quote whose
-- discount exceeds its design fee before the quote lines are inserted.
create or replace function api.reno_create_quote(p_customer_id uuid,p_quote_no text,p_version integer,p_quote_date date,p_design_fee numeric,p_tax numeric,p_discount numeric,p_items jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=custom_private.request_uid();v_designer uuid;v_quote uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'quote_create'); if v_existing is not null then return v_existing; end if;
 if not custom_private.reno_customer_allowed(p_customer_id) then raise exception using errcode='42501',message='reno_customer_forbidden';end if;
 if length(btrim(coalesce(p_quote_no,'')))=0 or coalesce(p_version,0)<1 or coalesce(p_design_fee,0)<0 or coalesce(p_tax,0)<0 or coalesce(p_discount,0)<0 or jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception using errcode='22023',message='reno_quote_invalid';end if;
 select coalesce(c.designer_id,c.owner_id) into v_designer from public.customers c where c.id=p_customer_id;
 insert into public.reno_quotes(customer_id,quote_no,version,designer_id,quote_date,design_fee,tax,discount,created_by)
 values(p_customer_id,p_quote_no,p_version,v_designer,coalesce(p_quote_date,current_date),coalesce(p_design_fee,0),coalesce(p_tax,0),0,v_actor) returning id into v_quote;
 insert into public.reno_quote_items(quote_id,line_no,space,category,item_name,spec,unit,quantity,unit_price,in_package,note)
 select v_quote,x.line_no,x.space,x.category,x.item_name,coalesce(x.spec,''),x.unit,x.quantity,x.unit_price,coalesce(x.in_package,false),coalesce(x.note,'')
 from jsonb_to_recordset(coalesce(p_items,'[]'::jsonb)) as x(line_no integer,space text,category text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,in_package boolean,note text)
 order by x.line_no;
 if not exists(select 1 from public.reno_quote_items i where i.quote_id=v_quote) then raise exception using errcode='22023',message='reno_quote_items_required';end if;
 update public.reno_quotes set discount=coalesce(p_discount,0) where id=v_quote;
 v_response:=jsonb_build_object('status','created','id',v_quote);perform custom_private.reno_store_receipt(p_request_id,'quote_create',v_quote,v_response);return v_response;
end $$;
alter function api.reno_create_quote(uuid,text,integer,date,numeric,numeric,numeric,jsonb,uuid) owner to anju_custom_executor;
revoke all on function api.reno_create_quote(uuid,text,integer,date,numeric,numeric,numeric,jsonb,uuid) from public,anon;
grant execute on function api.reno_create_quote(uuid,text,integer,date,numeric,numeric,numeric,jsonb,uuid) to authenticated,anju_custom_executor;
notify pgrst, 'reload schema';
