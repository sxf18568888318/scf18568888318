-- Repair executable payroll reads without changing payroll or business records.
-- Qualify every CTE column so RETURNS TABLE variables cannot shadow them.
-- Both UNION branches return exactly the five columns in the API contract.
begin;

create or replace function api.owner_factory_payroll(p_month date default null)
returns table(payroll_month date,employee_name text,pay_method text,amount numeric,source text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  return query
  with monthly as (
    select s.payroll_month::date as payroll_month,
      s.employee_name_snapshot as employee_name,
      '月薪'::text as pay_method,
      (s.amount+coalesce(adj.adjustments,0))::numeric as amount,
      '固定人工'::text as source
    from factory_private.monthly_payroll_snapshots s
    left join lateral (
      select sum(x.amount) as adjustments
      from factory_private.monthly_payroll_adjustments x
      where x.snapshot_id=s.id
    ) adj on true
    where p_month is null or s.payroll_month=date_trunc('month',p_month)::date
  ), attendance_rates as (
    select a.work_date,e.id as employee_id,e.employee_name,
      rate.pay_method,rate.pay_rate,a.attendance_status,a.piece_quantity
    from factory_private.attendance a
    join factory_private.employees e on e.id=a.employee_id
    cross join lateral (
      select h.pay_method,h.pay_rate
      from factory_private.employee_rate_history h
      where h.employee_id=e.id and h.effective_from<=a.work_date
      order by h.effective_from desc limit 1
    ) rate
    where rate.pay_method in ('日薪','计件')
      and (p_month is null or date_trunc('month',a.work_date)::date=date_trunc('month',p_month)::date)
  ), variable_monthly as (
    select date_trunc('month',ar.work_date)::date as payroll_month,
      ar.employee_name,ar.pay_method,
      sum(case
        when ar.pay_method='日薪' and ar.attendance_status in ('出勤','加班') then ar.pay_rate
        when ar.pay_method='计件' and ar.attendance_status in ('出勤','加班') then ar.pay_rate*ar.piece_quantity
        else 0 end)::numeric as amount,
      case ar.pay_method when '日薪' then '固定人工·按日薪×出勤天数'
        else '固定人工·按计件单价×数量' end::text as source
    from attendance_rates ar
    group by date_trunc('month',ar.work_date)::date,ar.employee_id,ar.employee_name,ar.pay_method
  )
  select combined.payroll_month,combined.employee_name,combined.pay_method,combined.amount,combined.source
  from (
    select m.payroll_month,m.employee_name,m.pay_method,m.amount,m.source from monthly m
    union all
    select v.payroll_month,v.employee_name,v.pay_method,v.amount,v.source from variable_monthly v
  ) combined
  order by combined.payroll_month desc,combined.employee_name;
end
$$;
alter function api.owner_factory_payroll(date) owner to anju_custom_executor;
revoke all on function api.owner_factory_payroll(date) from public,anon;
grant execute on function api.owner_factory_payroll(date) to authenticated;

notify pgrst,'reload schema';
commit;
