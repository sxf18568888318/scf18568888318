-- The factory's monthly payroll is public overhead. Keep historical per-order
-- labor ledger rows intact, but exclude them from order and factory gross views.
begin;

create or replace function api.owner_factory_work_orders()
returns table(
  id uuid,order_no text,customer_project text,business_source text,order_date date,delivery_date date,
  current_process text,status text,order_amount numeric,board_cost numeric,edge_cost numeric,
  hardware_cost numeric,processing_labor_cost numeric,outsourcing_cost numeric,other_cost numeric,
  total_cost numeric,gross_profit numeric,gross_margin numeric,completed_at timestamptz,note text
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query
  select w.id,w.order_no,w.customer_project,w.business_source,w.order_date,w.delivery_date,w.current_process,
    w.status,w.order_amount,
    coalesce(sum(c.amount) filter(where c.cost_category='板材'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='封边'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='五金'),0)::numeric,
    0::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='外协'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='其他'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category<>'加工人工'),0)::numeric,
    case when w.order_amount is null then null
      else w.order_amount-coalesce(sum(c.amount) filter(where c.cost_category<>'加工人工'),0) end,
    case when coalesce(w.order_amount,0)=0 then null
      else (w.order_amount-coalesce(sum(c.amount) filter(where c.cost_category<>'加工人工'),0))/w.order_amount end,
    w.completed_at,w.note
  from factory_private.work_orders w
  left join factory_private.order_cost_entries c on c.order_id=w.id
  group by w.id order by w.order_date desc,w.created_at desc;
end
$$;
alter function api.owner_factory_work_orders() owner to anju_custom_executor;
revoke all on function api.owner_factory_work_orders() from public,anon;
grant execute on function api.owner_factory_work_orders() to authenticated;

create or replace function api.owner_factory_order_cost_entries(p_order_id uuid)
returns table(
  id uuid,order_id uuid,cost_category text,amount numeric,source_type text,source_id uuid,
  reverses_entry_id uuid,note text,created_at timestamptz
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select c.id,c.order_id,c.cost_category,c.amount,c.source_type,c.source_id,
    c.reverses_entry_id,c.note,c.created_at
  from factory_private.order_cost_entries c
  where c.order_id=p_order_id and c.cost_category<>'加工人工'
  order by c.created_at,c.id;
end
$$;
alter function api.owner_factory_order_cost_entries(uuid) owner to anju_custom_executor;
revoke all on function api.owner_factory_order_cost_entries(uuid) from public,anon;
grant execute on function api.owner_factory_order_cost_entries(uuid) to authenticated;

create or replace function api.owner_factory_monthly_gross()
returns table(month date,factory_gross numeric,completed_order_count bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query
  select date_trunc('month',w.completed_at)::date,
    coalesce(sum(coalesce(w.order_amount,0)-coalesce(c.cost_total,0)),0)::numeric,count(*)::bigint
  from factory_private.work_orders w
  left join lateral (
    select sum(x.amount) cost_total from factory_private.order_cost_entries x
    where x.order_id=w.id and x.cost_category<>'加工人工'
  ) c on true
  where w.completed_at is not null and w.status in ('已完工','已结算')
  group by date_trunc('month',w.completed_at)::date order by 1;
end
$$;
alter function api.owner_factory_monthly_gross() owner to anju_custom_executor;
revoke all on function api.owner_factory_monthly_gross() from public,anon;
grant execute on function api.owner_factory_monthly_gross() to authenticated;

notify pgrst,'reload schema';
commit;
