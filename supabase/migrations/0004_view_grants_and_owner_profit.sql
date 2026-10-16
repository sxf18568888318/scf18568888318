-- 视图重建后重新授予 API 只读权限，并确保老板利润看板不受底层表权限影响。
-- 敏感字段仍只出现在 owner_factory_finance / owner_monthly_net_profit 中，
-- 这些视图内部都以 app.role() = 'owner' 做服务端过滤。

drop view if exists api.owner_monthly_net_profit;

create view api.owner_monthly_net_profit as
with month_list as (
  select date_trunc('month', q.created_at)::date as month,
    coalesce(sum(case when q.business_line='renovation' then q.amount - coalesce(dc.cost,0) else 0 end),0) as renovation_gross,
    coalesce(sum(case when q.business_line='custom' then q.amount - coalesce(dc.cost,0) else 0 end),0) as custom_gross
  from public.quotes q
  left join lateral (select sum(amount) cost from public.direct_costs d where d.customer_id=q.customer_id) dc on true
  group by date_trunc('month', q.created_at)::date
), factory_months as (
  select date_trunc('month', coalesce(order_date,created_at))::date as month,
    coalesce(sum(order_amount - (board_cost + edge_cost + hardware_cost + processing_labor_cost + outsourcing_cost + other_cost)),0) as factory_gross
  from public.factory_orders group by date_trunc('month', coalesce(order_date,created_at))::date
), all_months as (
  select month from month_list union select month from factory_months union select date_trunc('month',cost_month)::date from public.fixed_costs
), rows as (
  select a.month, coalesce(m.renovation_gross,0) renovation_gross, coalesce(m.custom_gross,0) custom_gross,
    coalesce(f.factory_gross,0) factory_gross,
    coalesce(m.renovation_gross,0)+coalesce(m.custom_gross,0)+coalesce(f.factory_gross,0) gross_total,
    coalesce((select sum(fc.amount) from public.fixed_costs fc where date_trunc('month',fc.cost_month)::date=a.month),0) fixed_cost
  from all_months a left join month_list m using(month) left join factory_months f using(month)
)
select month, renovation_gross, custom_gross, factory_gross, gross_total, fixed_cost,
  gross_total-fixed_cost as net_profit,
  sum(gross_total-fixed_cost) over(order by month rows between unbounded preceding and current row) as cumulative_net_profit
from rows where app.role()='owner' order by month;

grant select on api.factory_order_detail,
  api.owner_factory_finance,
  api.factory_employees_safe,
  api.inventory_balance,
  api.owner_monthly_net_profit
to authenticated;

