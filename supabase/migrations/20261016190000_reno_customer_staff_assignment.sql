-- List only role-safe assignee identities and bind renovation customers/orders
-- to real designer/foreman accounts. No business rows are changed by migration.
create or replace function api.reno_assignment_options()
returns table(user_id uuid, role_name text, display_name text)
language plpgsql stable security definer set search_path='' as $$
declare v_role text:=custom_private.request_role();
begin
  if v_role not in ('owner','designer') then
    raise exception using errcode='42501',message='reno_assignment_forbidden';
  end if;
  return query
    select u.id,
      case when u.raw_app_meta_data->>'role' in ('sales','designer') then 'designer' else 'foreman' end,
      coalesce(nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),
        case when u.raw_app_meta_data->>'role' in ('sales','designer') then '设计师' else '工长' end)
    from auth.users u
    where u.raw_app_meta_data->>'role' in ('sales','designer','foreman')
    order by 2,3;
end $$;
alter function api.reno_assignment_options() owner to postgres;
revoke all on function api.reno_assignment_options() from public,anon;
grant execute on function api.reno_assignment_options() to authenticated;

create or replace function api.reno_assign_customer_staff(
  p_customer_id uuid,p_designer_id uuid,p_foreman_id uuid,
  p_designer_name text,p_foreman_name text,p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid:=custom_private.request_uid();
  v_role text:=custom_private.request_role();
  v_customer public.customers%rowtype;
  v_designer uuid;
  v_response jsonb;
  v_existing jsonb;
begin
  perform custom_private.require_roles(array['owner','designer']);
  v_existing:=custom_private.reno_request_replay(p_request_id,'customer_staff_assignment');
  if v_existing is not null then return v_existing; end if;
  select * into v_customer from public.customers c
    where c.id=p_customer_id and c.business_line in ('reno','reno+custom') for update;
  if not found or not custom_private.reno_customer_allowed(p_customer_id) then
    raise exception using errcode='42501',message='reno_customer_forbidden';
  end if;
  if p_foreman_id is not null and not exists(
    select 1 from auth.users u where u.id=p_foreman_id and u.raw_app_meta_data->>'role'='foreman'
  ) then raise exception using errcode='22023',message='reno_foreman_invalid'; end if;
  if v_role='owner' then
    if p_designer_id is not null and not exists(
      select 1 from auth.users u where u.id=p_designer_id and u.raw_app_meta_data->>'role' in ('sales','designer')
    ) then raise exception using errcode='22023',message='reno_designer_invalid'; end if;
    v_designer:=p_designer_id;
  else
    v_designer:=v_actor;
    if coalesce(v_customer.designer_id,v_customer.owner_id)<>v_actor then
      raise exception using errcode='42501',message='reno_customer_forbidden';
    end if;
  end if;
  update public.customers set
    designer_id=v_designer,
    owner_id=case when v_role='owner' then coalesce(v_designer,owner_id) else owner_id end,
    foreman_id=p_foreman_id,
    designer_display_name=left(coalesce(nullif(p_designer_name,''),''),120),
    foreman_display_name=left(coalesce(nullif(p_foreman_name,''),''),120)
  where id=p_customer_id;
  update public.reno_orders set designer_id=coalesce(v_designer,designer_id),foreman_id=p_foreman_id
    where customer_id=p_customer_id;
  update public.reno_order_stages s set foreman_id=p_foreman_id
    from public.reno_orders o where o.id=s.order_id and o.customer_id=p_customer_id;
  v_response:=jsonb_build_object('status','saved','customer_id',p_customer_id);
  perform custom_private.reno_store_receipt(p_request_id,'customer_staff_assignment',p_customer_id,v_response);
  return v_response;
end $$;
alter function api.reno_assign_customer_staff(uuid,uuid,uuid,text,text,uuid) owner to postgres;
revoke all on function api.reno_assign_customer_staff(uuid,uuid,uuid,text,text,uuid) from public,anon;
grant execute on function api.reno_assign_customer_staff(uuid,uuid,uuid,text,text,uuid) to authenticated;
