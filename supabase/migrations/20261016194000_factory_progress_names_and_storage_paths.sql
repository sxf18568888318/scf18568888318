begin;

alter table factory_private.work_order_status_history
  add column if not exists operator_name text;

grant select, update on factory_private.work_orders to anju_custom_executor;
grant select, insert on factory_private.work_order_status_history to anju_custom_executor;

create or replace function api.factory_update_work_order_named(
  p_order_id uuid,
  p_process text,
  p_status text,
  p_operator_name text,
  p_request_id uuid
)
returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_old factory_private.work_orders%rowtype; v_dup boolean; v_name text:=btrim(coalesce(p_operator_name,''));
begin
  if custom_private.request_role() not in ('owner','factory_manager') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  if v_name='' or length(v_name)>100 or p_request_id is null then
    raise exception using errcode='22023',message='factory_invalid_operator';
  end if;
  if custom_private.request_role()='factory_manager' and (p_status in ('已完工','已结算') or p_process='已完工') then
    raise exception using errcode='42501',message='factory_owner_completion_required';
  end if;
  if p_process not in ('未排产','到货待开料','开料','封边','排钻','加工','试装','打包','安装','已完工')
     or p_status not in ('待开工','进行中','暂停','已完工','已结算') then
    raise exception using errcode='22023',message='factory_invalid_status';
  end if;
  v_dup:=factory_private.claim_request('factory_update_work_order_named',p_request_id,
    jsonb_build_object('order_id',p_order_id,'process',p_process,'status',p_status,'operator_name',v_name));
  if not v_dup then
    select * into v_old from factory_private.work_orders where id=p_order_id for update;
    if not found then raise exception using errcode='P0002',message='factory_order_not_found'; end if;
    update factory_private.work_orders set current_process=p_process,status=p_status,
      completed_at=case when p_status in ('已完工','已结算') then coalesce(completed_at,now()) else null end,
      updated_at=now() where id=p_order_id;
    insert into factory_private.work_order_status_history(order_id,old_status,new_status,old_process,new_process,changed_by,request_id,operator_name)
    values(p_order_id,v_old.status,p_status,v_old.current_process,p_process,custom_private.request_uid(),p_request_id,v_name);
  end if;
  return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_foreman_update_work_order_named(
  p_order_id uuid,
  p_process text,
  p_status text,
  p_operator_name text,
  p_request_id uuid
)
returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_old factory_private.work_orders%rowtype; v_dup boolean; v_name text:=btrim(coalesce(p_operator_name,''));
begin
  if custom_private.request_role()<>'foreman' or not factory_private.order_scope_allowed(p_order_id,'progress') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  if v_name='' or length(v_name)>100 or p_request_id is null
     or p_process not in ('未排产','到货待开料','开料','封边','排钻','加工','试装','打包','安装')
     or p_status not in ('进行中','暂停') then
    raise exception using errcode='22023',message='factory_invalid_progress';
  end if;
  v_dup:=factory_private.claim_request('factory_foreman_update_work_order_named',p_request_id,
    jsonb_build_object('order_id',p_order_id,'process',p_process,'status',p_status,'operator_name',v_name));
  if not v_dup then
    select * into v_old from factory_private.work_orders
      where id=p_order_id and foreman_id=custom_private.request_uid() and status not in ('已完工','已结算') for update;
    if not found then raise exception using errcode='42501',message='factory_forbidden'; end if;
    update factory_private.work_orders set current_process=p_process,status=p_status,updated_at=now() where id=p_order_id;
    insert into factory_private.work_order_status_history(order_id,old_status,new_status,old_process,new_process,changed_by,request_id,operator_name)
    values(p_order_id,v_old.status,p_status,v_old.current_process,p_process,custom_private.request_uid(),p_request_id,v_name);
  end if;
  return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_work_order_history_scoped(p_order_id uuid)
returns table(id uuid,order_id uuid,old_status text,new_status text,old_process text,new_process text,operator_name text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not factory_private.order_scope_allowed(p_order_id,'read') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  return query
    select h.id,h.order_id,h.old_status,h.new_status,h.old_process,h.new_process,h.operator_name,h.created_at
    from factory_private.work_order_status_history h
    where h.order_id=p_order_id order by h.created_at;
end $$;

-- New owner-only labor policy: payroll belongs to monthly factory overhead, never a single order.
create or replace function api.owner_record_factory_order_cost(p_order_id uuid,p_cost_category text,p_amount numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean;
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  if p_cost_category not in ('外协','其他') or p_amount<=0 or p_request_id is null then
    raise exception using errcode='22023',message='factory_invalid_cost';
  end if;
  v_dup:=factory_private.claim_request('owner_record_factory_order_cost',p_request_id,
    jsonb_build_object('order_id',p_order_id,'category',p_cost_category,'amount',p_amount,'note',p_note));
  if not v_dup then
    insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,note,created_by,request_id)
    values(p_order_id,p_cost_category,p_amount,'owner_entry',coalesce(p_note,''),custom_private.request_uid(),p_request_id);
  end if;
  return jsonb_build_object('status','ok');
end $$;

-- Storage keys use ASCII directory names so multiple invoice images and Excel files upload reliably.
create or replace function factory_private.order_storage_allowed(p_order_id uuid,p_name text,p_action text)
returns boolean
language plpgsql stable security definer set search_path=''
as $$
declare p text[]; v_order uuid; v_role text:=custom_private.request_role();
begin
  if p_name is null or p_name like '%..%' or p_action is null or p_action not in ('read','write')
     or not factory_private.order_scope_allowed(p_order_id,case when p_action='write' then 'progress' else 'read' end) then return false; end if;
  p:=string_to_array(p_name,'/');
  if array_length(p,1)<>5 or p[1]<>'factory' or p[2] !~* '^[0-9a-f-]{36}$'
     or p[3] not in ('图纸','板材单','五金单','合同','变更单','其他资料','现场照片','board','hardware','edging','drawings','contracts','changes','documents','site-photos','purchase','expense')
     or p[4] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or length(p[5])>180 then return false; end if;
  begin v_order:=p[2]::uuid; exception when others then return false; end;
  if v_order<>p_order_id then return false; end if;
  if p_action='write' then return v_role in ('owner','factory_manager','foreman') and factory_private.order_scope_allowed(p_order_id,'progress'); end if;
  if v_role<>'owner' and exists(
    select 1 from factory_private.order_documents d where d.order_id=p_order_id
      and d.storage_path=p_name and d.purchase_invoice_id is not null
  ) then return false; end if;
  return true;
end $$;

grant create on schema factory_private to anju_custom_executor;
alter function api.factory_update_work_order_named(uuid,text,text,text,uuid) owner to anju_custom_executor;
alter function api.factory_foreman_update_work_order_named(uuid,text,text,text,uuid) owner to anju_custom_executor;
alter function api.factory_work_order_history_scoped(uuid) owner to anju_custom_executor;
alter function api.owner_record_factory_order_cost(uuid,text,numeric,text,uuid) owner to anju_custom_executor;
alter function factory_private.order_storage_allowed(uuid,text,text) owner to anju_custom_executor;
revoke create on schema factory_private from anju_custom_executor;

revoke all on function api.factory_update_work_order_named(uuid,text,text,text,uuid),
  api.factory_foreman_update_work_order_named(uuid,text,text,text,uuid),
  api.factory_work_order_history_scoped(uuid),
  api.owner_record_factory_order_cost(uuid,text,numeric,text,uuid)
  from public,anon;
grant execute on function api.factory_update_work_order_named(uuid,text,text,text,uuid),
  api.factory_foreman_update_work_order_named(uuid,text,text,text,uuid),
  api.factory_work_order_history_scoped(uuid),
  api.owner_record_factory_order_cost(uuid,text,numeric,text,uuid)
  to authenticated;
revoke all on function factory_private.order_storage_allowed(uuid,text,text) from public,anon;
grant execute on function factory_private.order_storage_allowed(uuid,text,text) to authenticated;

notify pgrst,'reload schema';
commit;
