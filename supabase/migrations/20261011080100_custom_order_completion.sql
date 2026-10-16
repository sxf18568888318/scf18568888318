begin;

alter table public.factory_orders
  add column if not exists completed_at timestamptz;

create table if not exists public.custom_order_completion_events (
  id uuid primary key default gen_random_uuid(),
  factory_order_id uuid not null references public.factory_orders(id),
  action text not null check (action in ('complete','reopen')),
  previous_status text not null,
  previous_completed_at timestamptz,
  new_status text not null,
  new_completed_at timestamptz,
  note text not null default '',
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  request_id uuid not null unique
);
create index if not exists custom_order_completion_order_idx
  on public.custom_order_completion_events(factory_order_id, changed_at desc);
alter table public.custom_order_completion_events enable row level security;
revoke all on public.custom_order_completion_events from public,anon,authenticated;
grant select,insert on public.custom_order_completion_events to anju_custom_executor;
drop policy if exists custom_completion_event_owner on public.custom_order_completion_events;
create policy custom_completion_event_owner on public.custom_order_completion_events
  for all to anju_custom_executor
  using (app.role()='owner') with check (app.role()='owner');

create or replace function custom_private.read_owner_custom_order_completion_events()
returns table(
 id uuid,factory_order_id uuid,action text,previous_status text,previous_completed_at timestamptz,
 new_status text,new_completed_at timestamptz,note text,changed_by uuid,changed_at timestamptz,request_id uuid
)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query select e.id,e.factory_order_id,e.action,e.previous_status,e.previous_completed_at,
   e.new_status,e.new_completed_at,e.note,e.changed_by,e.changed_at,e.request_id
 from public.custom_order_completion_events e;
end
$$;
alter function custom_private.read_owner_custom_order_completion_events() owner to anju_custom_executor;
revoke all on function custom_private.read_owner_custom_order_completion_events() from public,anon,authenticated;
grant execute on function custom_private.read_owner_custom_order_completion_events() to anju_custom_executor;
grant execute on function custom_private.read_owner_custom_order_completion_events() to authenticated;
create view api.owner_custom_order_completion_events with(security_invoker=false) as
select * from custom_private.read_owner_custom_order_completion_events();
alter view api.owner_custom_order_completion_events owner to anju_custom_executor;
revoke all on api.owner_custom_order_completion_events from public,anon;
grant select on api.owner_custom_order_completion_events to authenticated;

create or replace function custom_private.owner_complete_order(
  p_order_id uuid,p_completed_at timestamptz,p_note text,p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_order public.factory_orders%rowtype;
  v_completed_at timestamptz := coalesce(p_completed_at,now());
  v_new_status text;
begin
  perform custom_private.require_roles(array['owner']);
  if p_request_id is null then
    raise exception using errcode='22023',message='custom_completion_request_id_required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
  if exists(select 1 from public.custom_order_completion_events e where e.request_id=p_request_id) then
    return jsonb_build_object('status','existing');
  end if;
  select * into v_order from public.factory_orders o
   where o.id=p_order_id and o.custom_quote_id is not null for update;
  if not found then
    raise exception using errcode='42501',message='custom_order_forbidden';
  end if;
  if v_order.completed_at is not null then
    return jsonb_build_object('status','existing');
  end if;
  v_new_status := case when v_order.status='已结算' then '已结算' else '已完工' end;
  update public.factory_orders
     set status=v_new_status,completed_at=v_completed_at
   where id=p_order_id;
  insert into public.custom_order_completion_events(
    factory_order_id,action,previous_status,previous_completed_at,new_status,new_completed_at,note,changed_by,request_id
  ) values (
    p_order_id,'complete',v_order.status,v_order.completed_at,v_new_status,v_completed_at,coalesce(p_note,''),custom_private.request_uid(),p_request_id
  );
  return jsonb_build_object('status','completed');
end
$$;
alter function custom_private.owner_complete_order(uuid,timestamptz,text,uuid) owner to anju_custom_executor;
revoke all on function custom_private.owner_complete_order(uuid,timestamptz,text,uuid) from public,anon;
grant execute on function custom_private.owner_complete_order(uuid,timestamptz,text,uuid) to authenticated;

create or replace function custom_private.owner_reopen_order(
  p_order_id uuid,p_note text,p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_order public.factory_orders%rowtype;
  v_restore_status text;
begin
  perform custom_private.require_roles(array['owner']);
  if p_request_id is null then
    raise exception using errcode='22023',message='custom_completion_request_id_required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
  if exists(select 1 from public.custom_order_completion_events e where e.request_id=p_request_id) then
    return jsonb_build_object('status','existing');
  end if;
  select * into v_order from public.factory_orders o
   where o.id=p_order_id and o.custom_quote_id is not null for update;
  if not found then
    raise exception using errcode='42501',message='custom_order_forbidden';
  end if;
  if v_order.completed_at is null then
    return jsonb_build_object('status','not_completed');
  end if;
  select e.previous_status into v_restore_status
    from public.custom_order_completion_events e
   where e.factory_order_id=p_order_id and e.action='complete'
   order by e.changed_at desc,e.id desc limit 1;
  v_restore_status := coalesce(v_restore_status,'进行中');
  update public.factory_orders set status=v_restore_status,completed_at=null where id=p_order_id;
  insert into public.custom_order_completion_events(
    factory_order_id,action,previous_status,previous_completed_at,new_status,new_completed_at,note,changed_by,request_id
  ) values (
    p_order_id,'reopen',v_order.status,v_order.completed_at,v_restore_status,null,coalesce(p_note,''),custom_private.request_uid(),p_request_id
  );
  return jsonb_build_object('status','reopened');
end
$$;
alter function custom_private.owner_reopen_order(uuid,text,uuid) owner to anju_custom_executor;
revoke all on function custom_private.owner_reopen_order(uuid,text,uuid) from public,anon;
grant execute on function custom_private.owner_reopen_order(uuid,text,uuid) to authenticated;

create or replace function api.custom_owner_complete_order(
  p_order_id uuid,p_completed_at timestamptz,p_note text,p_request_id uuid
) returns jsonb language sql security invoker set search_path='' as $$
  select custom_private.owner_complete_order(p_order_id,p_completed_at,p_note,p_request_id)
$$;
create or replace function api.custom_owner_reopen_order(
  p_order_id uuid,p_note text,p_request_id uuid
) returns jsonb language sql security invoker set search_path='' as $$
  select custom_private.owner_reopen_order(p_order_id,p_note,p_request_id)
$$;
revoke all on function api.custom_owner_complete_order(uuid,timestamptz,text,uuid) from public,anon;
revoke all on function api.custom_owner_reopen_order(uuid,text,uuid) from public,anon;
grant execute on function api.custom_owner_complete_order(uuid,timestamptz,text,uuid) to authenticated;
grant execute on function api.custom_owner_reopen_order(uuid,text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
