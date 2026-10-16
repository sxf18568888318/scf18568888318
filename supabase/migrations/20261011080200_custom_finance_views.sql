begin;

-- Give the non-BYPASSRLS executor narrowly scoped owner-only reads for the
-- legacy tables used in the combined owner finance rollup.
grant select on public.quotes,public.direct_costs,public.factory_orders,public.fixed_costs to anju_custom_executor;
drop policy if exists custom_step7_finance_owner_quotes on public.quotes;
create policy custom_step7_finance_owner_quotes on public.quotes
  for select to anju_custom_executor using (app.role()='owner');
drop policy if exists custom_step7_finance_owner_direct_costs on public.direct_costs;
create policy custom_step7_finance_owner_direct_costs on public.direct_costs
  for select to anju_custom_executor using (app.role()='owner');
drop policy if exists custom_step7_finance_owner_fixed_costs on public.fixed_costs;
create policy custom_step7_finance_owner_fixed_costs on public.fixed_costs
  for select to anju_custom_executor using (app.role()='owner');

drop view if exists api.owner_custom_order_profit;
drop function if exists custom_private.read_owner_custom_order_profit();

create or replace function custom_private.read_owner_custom_order_profit_step7()
returns table(
 factory_order_id uuid,customer_id uuid,custom_quote_id uuid,status text,completed_at timestamptz,
 sales_amount numeric,board_cost numeric,hardware_cost numeric,edge_cost numeric,labor_cost numeric,
 installation_cost numeric,outsourcing_cost numeric,other_cost numeric,cost_total numeric,
 gross_profit numeric,gross_margin numeric,allocated_purchase_reference numeric,
 issued_material_net_cost numeric,reconciliation_difference numeric,is_work_in_progress boolean
)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query
 with costs as (
   select c.factory_order_id,
     coalesce(sum(c.amount) filter(where c.category='板材'),0)::numeric board_cost,
     coalesce(sum(c.amount) filter(where c.category='五金'),0)::numeric hardware_cost,
     coalesce(sum(c.amount) filter(where c.category='封边'),0)::numeric edge_cost,
     coalesce(sum(c.amount) filter(where c.category='人工'),0)::numeric labor_cost,
     coalesce(sum(c.amount) filter(where c.category='安装'),0)::numeric installation_cost,
     coalesce(sum(c.amount) filter(where c.category='外协'),0)::numeric outsourcing_cost,
     coalesce(sum(c.amount) filter(where c.category='其他'),0)::numeric other_cost,
     coalesce(sum(c.amount),0)::numeric cost_total
   from public.custom_cost_entries c group by c.factory_order_id
 ), allocations as (
   select a.factory_order_id,coalesce(sum(a.allocated_amount),0)::numeric allocated_reference
   from public.custom_purchase_allocations a group by a.factory_order_id
 )
 select o.id,o.customer_id,o.custom_quote_id,o.status,o.completed_at,
   coalesce(o.order_amount,0)::numeric,
   coalesce(c.board_cost,0),coalesce(c.hardware_cost,0),coalesce(c.edge_cost,0),coalesce(c.labor_cost,0),
   coalesce(c.installation_cost,0),coalesce(c.outsourcing_cost,0),coalesce(c.other_cost,0),coalesce(c.cost_total,0),
   coalesce(o.order_amount,0)-coalesce(c.cost_total,0),
   case when coalesce(o.order_amount,0)=0 then null::numeric
        else (coalesce(o.order_amount,0)-coalesce(c.cost_total,0))/o.order_amount end,
   coalesce(a.allocated_reference,0),coalesce(c.board_cost,0)+coalesce(c.hardware_cost,0),
   coalesce(a.allocated_reference,0)-coalesce(c.board_cost,0)-coalesce(c.hardware_cost,0),
   o.completed_at is null
 from public.factory_orders o
 left join costs c on c.factory_order_id=o.id
 left join allocations a on a.factory_order_id=o.id
 where o.custom_quote_id is not null;
end
$$;
alter function custom_private.read_owner_custom_order_profit_step7() owner to anju_custom_executor;
revoke all on function custom_private.read_owner_custom_order_profit_step7() from public,anon;
grant execute on function custom_private.read_owner_custom_order_profit_step7() to anju_custom_executor,authenticated;
create view api.owner_custom_order_profit with(security_invoker=false) as
select * from custom_private.read_owner_custom_order_profit_step7();
alter view api.owner_custom_order_profit owner to anju_custom_executor;
revoke all on api.owner_custom_order_profit from public,anon;
grant select on api.owner_custom_order_profit to authenticated;

drop view if exists api.owner_monthly_net_profit;

create or replace function custom_private.read_owner_monthly_net_profit_step7()
returns table(
 month date,renovation_gross numeric,custom_gross numeric,factory_gross numeric,gross_total numeric,
 fixed_cost numeric,net_profit numeric,cumulative_net_profit numeric,custom_completed_order_count bigint
)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query
 with renovation_months as (
   select date_trunc('month',q.created_at)::date as month,
     coalesce(sum(q.amount-coalesce(dc.cost,0)),0)::numeric as renovation_gross
   from public.quotes q
   left join lateral (select sum(d.amount) cost from public.direct_costs d where d.customer_id=q.customer_id) dc on true
   where q.business_line='renovation'
   group by date_trunc('month',q.created_at)::date
 ), legacy_factory_months as (
   select date_trunc('month',coalesce(o.order_date,o.created_at))::date as month,
     coalesce(sum(coalesce(o.order_amount,0)-coalesce(o.board_cost,0)-coalesce(o.edge_cost,0)-coalesce(o.hardware_cost,0)
       -coalesce(o.processing_labor_cost,0)-coalesce(o.outsourcing_cost,0)-coalesce(o.other_cost,0)),0)::numeric as factory_gross
   from public.factory_orders o
   where o.custom_quote_id is null
   group by date_trunc('month',coalesce(o.order_date,o.created_at))::date
 ), custom_completed_months as (
   select date_trunc('month',o.completed_at)::date as month,
     coalesce(sum(coalesce(o.order_amount,0)-coalesce(p.cost_total,0)),0)::numeric as custom_gross,
     count(*)::bigint as order_count
   from public.factory_orders o
   left join lateral (select sum(c.amount) cost_total from public.custom_cost_entries c where c.factory_order_id=o.id) p on true
   where o.custom_quote_id is not null and o.completed_at is not null and o.status in ('已完工','已结算')
   group by date_trunc('month',o.completed_at)::date
 ), fixed_cost_months as (
   select date_trunc('month',f.cost_month)::date as month,coalesce(sum(f.amount),0)::numeric as fixed_cost
   from public.fixed_costs f group by date_trunc('month',f.cost_month)::date
 ), months as (
   select r.month from renovation_months r union
   select f.month from legacy_factory_months f union
   select c.month from custom_completed_months c union
   select fc.month from fixed_cost_months fc
 ), rows as (
   select m.month,coalesce(r.renovation_gross,0)::numeric renovation_gross,
     coalesce(c.custom_gross,0)::numeric custom_gross,coalesce(f.factory_gross,0)::numeric factory_gross,
     coalesce(r.renovation_gross,0)+coalesce(c.custom_gross,0)+coalesce(f.factory_gross,0) gross_total,
     coalesce(fc.fixed_cost,0)::numeric fixed_cost,coalesce(c.order_count,0)::bigint custom_completed_order_count
   from months m
   left join renovation_months r using(month)
   left join legacy_factory_months f using(month)
   left join custom_completed_months c using(month)
   left join fixed_cost_months fc using(month)
 )
 select rows.month,rows.renovation_gross,rows.custom_gross,rows.factory_gross,rows.gross_total,rows.fixed_cost,
   rows.gross_total-rows.fixed_cost,
   sum(rows.gross_total-rows.fixed_cost) over(order by rows.month rows between unbounded preceding and current row),
   rows.custom_completed_order_count
 from rows order by rows.month;
end
$$;
alter function custom_private.read_owner_monthly_net_profit_step7() owner to anju_custom_executor;
revoke all on function custom_private.read_owner_monthly_net_profit_step7() from public,anon;
grant execute on function custom_private.read_owner_monthly_net_profit_step7() to anju_custom_executor,authenticated;
create view api.owner_monthly_net_profit with(security_invoker=false) as
select * from custom_private.read_owner_monthly_net_profit_step7();
alter view api.owner_monthly_net_profit owner to anju_custom_executor;
revoke all on api.owner_monthly_net_profit from public,anon;
grant select on api.owner_monthly_net_profit to authenticated,anju_custom_executor;

create or replace function custom_private.read_owner_yearly_net_profit_step7()
returns table(
 year integer,renovation_gross numeric,custom_gross numeric,factory_gross numeric,gross_total numeric,
 fixed_cost numeric,net_profit numeric,custom_completed_order_count bigint
)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query
 select extract(year from m.month)::integer,
   coalesce(sum(m.renovation_gross),0)::numeric,coalesce(sum(m.custom_gross),0)::numeric,
   coalesce(sum(m.factory_gross),0)::numeric,coalesce(sum(m.gross_total),0)::numeric,
   coalesce(sum(m.fixed_cost),0)::numeric,coalesce(sum(m.net_profit),0)::numeric,
   coalesce(sum(m.custom_completed_order_count),0)::bigint
 from custom_private.read_owner_monthly_net_profit_step7() m
 group by extract(year from m.month);
end
$$;
alter function custom_private.read_owner_yearly_net_profit_step7() owner to anju_custom_executor;
revoke all on function custom_private.read_owner_yearly_net_profit_step7() from public,anon;
grant execute on function custom_private.read_owner_yearly_net_profit_step7() to anju_custom_executor,authenticated;
create or replace view api.owner_yearly_net_profit with(security_invoker=false) as
select * from custom_private.read_owner_yearly_net_profit_step7();
alter view api.owner_yearly_net_profit owner to anju_custom_executor;
revoke all on api.owner_yearly_net_profit from public,anon;
grant select on api.owner_yearly_net_profit to authenticated;

notify pgrst,'reload schema';
commit;
