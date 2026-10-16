begin;

-- Foremen may attach progress photos to orders assigned to them. Other
-- production documents remain restricted to owners and factory managers.
create or replace function api.factory_register_order_document(
 p_order_id uuid,p_kind text,p_file_name text,p_storage_path text,p_mime_type text,
 p_file_size bigint,p_version text,p_note text,p_request_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare v_dup boolean; v_id uuid; v_role text:=custom_private.request_role();
begin
 if p_kind='现场照片' then
   if v_role not in ('owner','factory_manager','foreman') or not factory_private.order_scope_allowed(p_order_id,'progress') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 else
   if v_role not in ('owner','factory_manager') or not factory_private.order_scope_allowed(p_order_id,'write') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 end if;
 if p_request_id is null or p_kind not in ('图纸','板材单','五金单','合同','变更单','其他资料','现场照片')
   or p_file_size is null or p_file_size<=0 or p_file_size>31457280
   or p_mime_type not in ('image/jpeg','image/png','image/webp','application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel')
   or not factory_private.order_storage_allowed(p_order_id,p_storage_path,'write') then
   raise exception using errcode='42501',message='factory_document_forbidden';
 end if;
 v_dup:=factory_private.claim_request('factory_register_order_document',p_request_id,jsonb_build_object('order',p_order_id,'kind',p_kind,'path',p_storage_path,'name',p_file_name,'mime',p_mime_type,'size',p_file_size,'version',p_version,'note',p_note));
 if not v_dup then
   insert into factory_private.order_documents(order_id,document_kind,file_name,storage_path,mime_type,file_size,version_label,note,created_by,request_id)
   values(p_order_id,p_kind,left(p_file_name,255),p_storage_path,p_mime_type,p_file_size,left(coalesce(p_version,''),60),left(coalesce(p_note,''),1000),custom_private.request_uid(),p_request_id)
   returning id into v_id;
 end if;
 return jsonb_build_object('status','ok');
end $$;
alter function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) from public,anon;
grant execute on function api.factory_register_order_document(uuid,text,text,text,text,bigint,text,text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
