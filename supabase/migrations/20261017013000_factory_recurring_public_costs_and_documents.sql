begin;

alter table public.fixed_costs add column if not exists cost_mode text not null default 'monthly';
alter table public.fixed_costs add column if not exists annual_amount numeric(14,2);
alter table public.fixed_costs add column if not exists allocation_group_id uuid;
alter table public.fixed_costs drop constraint if exists fixed_costs_cost_mode_check;
alter table public.fixed_costs add constraint fixed_costs_cost_mode_check check(cost_mode in ('monthly','annual','one_time'));

create or replace function api.factory_record_public_cost_v2(p_cost_month date,p_category text,p_item text,p_amount numeric,p_cost_mode text,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_category text; v_item text; v_group uuid:=gen_random_uuid(); v_month date; v_month_amount numeric(14,2); v_i integer;
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_cost_month is null or p_amount is null or p_amount<=0 or p_request_id is null or p_cost_mode not in ('monthly','annual','one_time') or length(btrim(coalesce(p_category,'')))=0 or length(btrim(p_category))>100 or length(btrim(coalesce(p_item,'')))>160 then raise exception using errcode='22023',message='factory_invalid_public_cost'; end if;
  v_category:=case when p_category in ('房租','水电','固定人工','折旧','办公软件','营销推广','其他') then p_category else '其他' end;
  v_item:=case when p_category=v_category then left(btrim(coalesce(p_item,'')),160) else concat_ws(' · ',left(btrim(p_category),100),nullif(left(btrim(coalesce(p_item,'')),160),'')) end;
  v_dup:=factory_private.claim_request('factory_record_public_cost_v2',p_request_id,jsonb_build_object('month',date_trunc('month',p_cost_month)::date,'category',p_category,'item',p_item,'amount',p_amount,'mode',p_cost_mode,'note',p_note));
  if not v_dup then
    if p_cost_mode='annual' then
      v_month_amount:=round(p_amount/12,2);
      for v_i in 0..11 loop
        v_month:=(date_trunc('year',p_cost_month)::date + make_interval(months=>v_i))::date;
        insert into public.fixed_costs(cost_month,category,amount,note,item,ownership,created_by,request_id,cost_mode,annual_amount,allocation_group_id)
        values(v_month,v_category,case when v_i=11 then p_amount-v_month_amount*11 else v_month_amount end,left(coalesce(p_note,''),1000),v_item,'工厂',custom_private.request_uid(),gen_random_uuid(),'annual',p_amount,v_group);
      end loop;
    else
      insert into public.fixed_costs(cost_month,category,amount,note,item,ownership,created_by,request_id,cost_mode,annual_amount,allocation_group_id)
      values(date_trunc('month',p_cost_month)::date,v_category,p_amount,left(coalesce(p_note,''),1000),v_item,'工厂',custom_private.request_uid(),p_request_id,p_cost_mode,null,v_group);
    end if;
  end if;
  return jsonb_build_object('status','ok','allocation_group_id',v_group);
end $$;
alter function api.factory_record_public_cost_v2(date,text,text,numeric,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_record_public_cost_v2(date,text,text,numeric,text,text,uuid) from public,anon;
grant execute on function api.factory_record_public_cost_v2(date,text,text,numeric,text,text,uuid) to authenticated;

create or replace function api.factory_manager_fixed_costs_v2(p_month date default null)
returns table(id uuid,cost_month date,category text,item text,amount numeric,ownership text,note text,cost_mode text,annual_amount numeric,allocation_group_id uuid)
language plpgsql stable security definer set search_path=''
as $$ begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select f.id,f.cost_month,f.category,f.item,f.amount,f.ownership,f.note,f.cost_mode,f.annual_amount,f.allocation_group_id from public.fixed_costs f
    where f.ownership='工厂' and (p_month is null or date_trunc('month',f.cost_month)::date=date_trunc('month',p_month)::date)
    order by f.cost_month desc,f.created_at desc;
end $$;
alter function api.factory_manager_fixed_costs_v2(date) owner to anju_custom_executor;
revoke all on function api.factory_manager_fixed_costs_v2(date) from public,anon;
grant execute on function api.factory_manager_fixed_costs_v2(date) to authenticated;

alter table factory_private.order_documents drop constraint if exists order_documents_document_kind_check;
alter table factory_private.order_documents add constraint order_documents_document_kind_check
  check(document_kind in ('订货单','五金清单','特殊备注','图纸','板材单','五金单','合同','报价单','变更单','其他资料','现场照片'));
create or replace function api.factory_register_order_document(p_order_id uuid,p_kind text,p_file_name text,p_storage_path text,p_mime_type text,p_file_size bigint,p_version text,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$ declare v_dup boolean; v_id uuid;
begin
  if custom_private.request_role() not in ('owner','factory_manager') or p_request_id is null or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_kind not in ('订货单','五金清单','特殊备注','图纸','板材单','五金单','合同','报价单','变更单','其他资料','现场照片') or p_file_size is null or p_file_size<=0 or p_file_size>31457280 or not factory_private.order_storage_allowed(p_order_id,p_storage_path,'write') then raise exception using errcode='42501',message='factory_document_forbidden'; end if;
  v_dup:=factory_private.claim_request('factory_register_order_document',p_request_id,jsonb_build_object('order',p_order_id,'kind',p_kind,'path',p_storage_path,'name',p_file_name,'mime',p_mime_type,'size',p_file_size,'version',p_version,'note',p_note));
  if not v_dup then insert into factory_private.order_documents(order_id,document_kind,file_name,storage_path,mime_type,file_size,version_label,note,created_by,request_id)
    values(p_order_id,p_kind,left(p_file_name,255),p_storage_path,p_mime_type,p_file_size,left(coalesce(p_version,''),60),left(coalesce(p_note,''),1000),custom_private.request_uid(),p_request_id) returning id into v_id; end if;
  return jsonb_build_object('status','ok','id',v_id);
end $$;
alter function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) from public,anon;
grant execute on function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) to authenticated;

drop policy if exists factory_files_delete on storage.objects;
create policy factory_files_delete on storage.objects for delete to authenticated
  using(bucket_id='factory-files' and factory_private.document_path_allowed(name,'write'));

notify pgrst, 'reload schema';
commit;

