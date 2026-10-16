begin;

create or replace function api.factory_foreman_update_work_order(p_order_id uuid,p_process text,p_status text,p_request_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean;
begin
 if custom_private.request_role()<>'foreman' or not factory_private.order_scope_allowed(p_order_id,'progress') then
   raise exception using errcode='42501',message='factory_forbidden';
 end if;
 if p_process not in ('未排产','到货待开料','开料','封边','排钻','加工','试装','打包','安装')
   or p_status not in ('进行中','暂停') or p_request_id is null then
   raise exception using errcode='22023',message='factory_invalid_progress';
 end if;
 v_dup:=factory_private.claim_request('factory_foreman_update_work_order',p_request_id,jsonb_build_object('order_id',p_order_id,'process',p_process,'status',p_status));
 if not v_dup then
   update factory_private.work_orders set current_process=p_process,status=p_status,updated_at=now()
    where id=p_order_id and foreman_id=custom_private.request_uid() and status not in ('已完工','已结算');
   if not found then raise exception using errcode='42501',message='factory_forbidden'; end if;
 end if;
 return jsonb_build_object('status','ok');
end $$;
alter function api.factory_foreman_update_work_order(uuid,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_foreman_update_work_order(uuid,text,text,uuid) from public,anon;
grant execute on function api.factory_foreman_update_work_order(uuid,text,text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
