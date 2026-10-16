-- Read-only adapters for existing ledgers. No business rows, tables, policies,
-- or existing RPC/view behavior are changed.
begin;

create or replace function api.owner_business_accounts()
returns table(business_line text, period_kind text, period date,
              gross_profit numeric, fixed_cost numeric, net_profit numeric)
language plpgsql stable security definer set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner']);
  return query
  with base as (select * from custom_private.read_owner_monthly_net_profit_factory()),
  fixed as (
    select date_trunc('month', f.cost_month)::date as month,
      sum(f.amount)::numeric as total,
      sum(case when f.ownership in ('整装','整装业务','renovation','reno') then f.amount else 0 end)::numeric as reno,
      sum(case when f.ownership in ('定制','全屋定制','custom') then f.amount else 0 end)::numeric as custom,
      sum(case when f.ownership in ('工厂','工厂生产','factory') then f.amount else 0 end)::numeric as factory,
      sum(case when coalesce(f.ownership,'') not in ('整装','整装业务','renovation','reno','定制','全屋定制','custom','工厂','工厂生产','factory') then f.amount else 0 end)::numeric as shared
    from public.fixed_costs f group by 1
  ), monthly as (
    select d.business_line, b.month,
      (case d.business_line when 'reno' then b.renovation_gross when 'custom' then b.custom_gross when 'factory' then b.factory_gross else 0 end)::numeric as gross,
      (case d.business_line when 'reno' then coalesce(f.reno,0) when 'custom' then coalesce(f.custom,0)
        when 'factory' then coalesce(f.factory,0) + b.fixed_cost - coalesce(f.total,0)
        else coalesce(f.shared,0) end)::numeric as fixed
    from base b left join fixed f on f.month=b.month
    cross join (values ('reno'::text),('custom'::text),('factory'::text),('shared'::text)) d(business_line)
  )
  select m.business_line,'month'::text,m.month,m.gross,m.fixed,m.gross-m.fixed from monthly m
  union all
  select m.business_line,'year'::text,date_trunc('year',m.month)::date,
    sum(m.gross)::numeric,sum(m.fixed)::numeric,sum(m.gross-m.fixed)::numeric
  from monthly m group by m.business_line,date_trunc('year',m.month)::date;
end
$$;

create or replace function api.factory_work_order_history_safe(p_order_id uuid)
returns table(id uuid, order_id uuid, old_status text, new_status text,
              old_process text, new_process text, changed_by uuid, created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner','factory_manager']);
  return query select h.id,h.order_id,h.old_status,h.new_status,h.old_process,h.new_process,h.changed_by,h.created_at
    from factory_private.work_order_status_history h where h.order_id=p_order_id order by h.created_at;
end
$$;

create or replace function api.owner_factory_attendance_costs()
returns table(attendance_id uuid, employee_id uuid, employee_name text,
              work_date date, allocated_amount numeric)
language plpgsql stable security definer set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner']);
  return query
    select a.id,a.employee_id,e.employee_name,a.work_date,coalesce(sum(c.amount),0)::numeric
    from factory_private.attendance a
    join factory_private.employees e on e.id=a.employee_id
    left join factory_private.attendance_allocations x on x.attendance_id=a.id
    left join factory_private.order_cost_entries c on c.source_id=x.id and c.source_type='attendance'
    group by a.id,e.employee_name order by a.work_date;
end
$$;

alter function api.owner_business_accounts() owner to anju_custom_executor;
alter function api.factory_work_order_history_safe(uuid) owner to anju_custom_executor;
alter function api.owner_factory_attendance_costs() owner to anju_custom_executor;
revoke all on function api.owner_business_accounts(), api.factory_work_order_history_safe(uuid), api.owner_factory_attendance_costs() from public, anon;
grant execute on function api.owner_business_accounts(), api.factory_work_order_history_safe(uuid), api.owner_factory_attendance_costs() to authenticated;
notify pgrst,'reload schema';
commit;
