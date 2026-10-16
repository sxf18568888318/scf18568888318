drop function if exists api.factory_employees_safe();

create function api.factory_employees_safe()
returns table(
  id uuid,
  employee_name text,
  job text,
  employment_status text,
  pay_method text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if custom_private.request_role() not in ('owner', 'factory_manager') then
    raise exception using errcode='42501', message='factory_forbidden';
  end if;

  return query
  select e.id, e.employee_name, e.job, e.employment_status, e.pay_method
  from factory_private.employees e
  order by e.employee_name;
end;
$$;

alter function api.factory_employees_safe() owner to anju_custom_executor;
revoke all on function api.factory_employees_safe() from public, anon;
grant execute on function api.factory_employees_safe() to authenticated;
