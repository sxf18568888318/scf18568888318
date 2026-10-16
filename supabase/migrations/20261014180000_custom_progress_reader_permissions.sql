-- Keep the existing REST view and its sales-only column contract. Execute the
-- table/RLS read inside the already-scoped executor, never grant request_uid
-- or sensitive base-table access to browser roles.
begin;

grant execute on function custom_private.request_uid(), custom_private.request_role()
  to anju_custom_executor;

create or replace function custom_private.read_custom_factory_progress()
returns table(quote_id uuid, customer_id uuid, status text, current_process text,
              order_date date, delivery_date date, completed_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner','designer']);
  return query
    select f.custom_quote_id, f.customer_id, f.status, f.current_process,
           f.order_date, f.delivery_date, f.completed_at
      from public.factory_orders f
     where f.custom_quote_id is not null
       and custom_private.customer_allowed(f.customer_id);
end
$$;
alter function custom_private.read_custom_factory_progress() owner to anju_custom_executor;
revoke all on function custom_private.read_custom_factory_progress() from public, anon;
grant execute on function custom_private.read_custom_factory_progress() to authenticated;

create or replace view api.custom_factory_progress with(security_invoker=false) as
  select * from custom_private.read_custom_factory_progress();
alter view api.custom_factory_progress owner to anju_custom_executor;
revoke all on api.custom_factory_progress from public, anon;
grant select on api.custom_factory_progress to authenticated;

notify pgrst, 'reload schema';
commit;
