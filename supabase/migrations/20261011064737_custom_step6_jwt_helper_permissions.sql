-- Step 6 P0: route custom executor paths through the scoped JWT helpers. The
-- executor and authenticated roles must not need USAGE on the app/auth schemas.
-- P1.1: factory managers may update production status only through the legacy
-- order RPC; cost totals remain derived from the custom cost ledger.
begin;

revoke all on function custom_private.request_uid() from public, anon, authenticated;
grant execute on function custom_private.request_uid() to anju_custom_executor;
revoke all on function custom_private.request_role() from public, anon;
grant execute on function custom_private.request_role() to authenticated, anju_custom_executor;

-- Replace legacy role / identity lookups in executor-owned SECURITY DEFINER
-- functions while preserving each function's owner, security mode, and grants.
do $functions$
declare
  r record;
  definition text;
begin
  for r in
    select p.oid, pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind = 'f'
      and n.nspname = 'custom_private'
      and p.proowner = 'anju_custom_executor'::regrole
      and (
        position('app.role()' in lower(pg_get_functiondef(p.oid))) > 0
        or position('auth.uid()' in lower(pg_get_functiondef(p.oid))) > 0
      )
  loop
    definition := replace(r.definition, 'app.role()', 'custom_private.request_role()');
    definition := replace(definition, 'auth.uid()', 'custom_private.request_uid()');
    execute definition;
  end loop;

  -- API invoker wrappers run as the caller, so they also cannot invoke
  -- app.role() when authenticated lacks app-schema USAGE.
  for r in
    select p.oid, pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind = 'f'
      and n.nspname = 'api'
      and p.proname like 'custom\_%' escape '\'
      and (
        position('app.role()' in lower(pg_get_functiondef(p.oid))) > 0
        or position('auth.uid()' in lower(pg_get_functiondef(p.oid))) > 0
      )
  loop
    definition := replace(r.definition, 'app.role()', 'custom_private.request_role()');
    definition := replace(definition, 'auth.uid()', 'custom_private.request_uid()');
    execute definition;
  end loop;
end
$functions$;

-- RLS executes as the function owner. Rewrite every executor-targeted policy
-- that still resolves role / UID through app or auth directly.
do $policies$
declare
  r record;
  statement text;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where 'anju_custom_executor' = any(roles)
      and (
        position('app.role()' in lower(coalesce(qual, ''))) > 0
        or position('app.role()' in lower(coalesce(with_check, ''))) > 0
        or position('auth.uid()' in lower(coalesce(qual, ''))) > 0
        or position('auth.uid()' in lower(coalesce(with_check, ''))) > 0
      )
  loop
    statement := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if r.qual is not null then
      statement := statement || format(
        ' using (%s)',
        replace(replace(r.qual, 'app.role()', 'custom_private.request_role()'), 'auth.uid()', 'custom_private.request_uid()')
      );
    end if;
    if r.with_check is not null then
      statement := statement || format(
        ' with check (%s)',
        replace(replace(r.with_check, 'app.role()', 'custom_private.request_role()'), 'auth.uid()', 'custom_private.request_uid()')
      );
    end if;
    execute statement;
  end loop;
end
$policies$;

-- Factory managers receive only a success status from edge-cost recording.
create or replace function api.custom_record_edge_processing(
  p_order_id uuid, p_edge_process text, p_processing_mode text,
  p_length_m numeric, p_date date
) returns jsonb
language sql security invoker set search_path = '' as $$
  select case when custom_private.request_role() = 'factory_manager'
    then jsonb_build_object('status', custom_private.record_edge_processing(
      p_order_id, p_edge_process, p_processing_mode, p_length_m, p_date
    )->>'status')
    else custom_private.record_edge_processing(
      p_order_id, p_edge_process, p_processing_mode, p_length_m, p_date
    )
  end
$$;
revoke all on function api.custom_record_edge_processing(uuid, text, text, numeric, date) from public, anon;
grant execute on function api.custom_record_edge_processing(uuid, text, text, numeric, date) to authenticated;

-- Keep this legacy RPC for production status updates, but prevent the factory
-- role from supplying or overwriting any cost summary columns.
create or replace function api.factory_update_order(
  p_order_id uuid, p_current_process text, p_status text,
  p_board_cost numeric, p_edge_cost numeric, p_hardware_cost numeric,
  p_processing_labor_cost numeric, p_outsourcing_cost numeric, p_other_cost numeric,
  p_note text default ''
) returns void
language plpgsql security definer
set search_path = pg_catalog, public, custom_private
as $$
declare
  actor_role text := custom_private.request_role();
  actor_id uuid := custom_private.request_uid();
begin
  if actor_role = 'owner' then
    update public.factory_orders
    set current_process = p_current_process,
        status = p_status,
        board_cost = coalesce(p_board_cost, 0),
        edge_cost = coalesce(p_edge_cost, 0),
        hardware_cost = coalesce(p_hardware_cost, 0),
        processing_labor_cost = coalesce(p_processing_labor_cost, 0),
        outsourcing_cost = coalesce(p_outsourcing_cost, 0),
        other_cost = coalesce(p_other_cost, 0),
        note = coalesce(p_note, '')
    where id = p_order_id;
  elsif actor_role = 'factory_manager' then
    update public.factory_orders
    set current_process = p_current_process,
        status = p_status,
        note = coalesce(p_note, '')
    where id = p_order_id
      and factory_manager_id = actor_id;
  else
    raise exception 'forbidden';
  end if;

  if not found then
    raise exception 'not_found_or_forbidden';
  end if;
end
$$;
revoke all on function api.factory_update_order(uuid, text, text, numeric, numeric, numeric, numeric, numeric, numeric, text) from public, anon;
grant execute on function api.factory_update_order(uuid, text, text, numeric, numeric, numeric, numeric, numeric, numeric, text) to authenticated;

notify pgrst, 'reload schema';
commit;
