-- 严格按《板材五金档案与BOM样板》和《工厂生产与净利样板》扩展。
-- 说明文字与单元格公式存在差异时，以表中实际公式为准。

create table if not exists public.board_catalog (
  id uuid primary key default gen_random_uuid(),
  material_name text not null,
  category_use text not null check (category_use in ('柜体板','柜门','见光板','背板','层板','通用')),
  brand text not null default '',
  substrate text not null check (substrate in ('颗粒板','多层板','OSB','实木板','密度板')),
  thickness_mm numeric(8,2) not null default 18,
  color_name text not null default '',
  color_code text not null default '',
  finish_process text not null check (finish_process in ('双饰面','PET','吸塑','高光','烤漆','亚克力','实木贴皮')),
  eco_grade text not null check (eco_grade in ('E1','E0','ENF')),
  edge_process text not null check (edge_process in ('EVA','PUR','激光','无')),
  standard_size text not null default '',
  pricing_method text not null check (pricing_method in ('按张','按㎡','按延米','按个')),
  reference_purchase_price numeric(14,2) not null default 0,
  default_supplier text not null default '',
  status text not null default '在用' check (status in ('在用','备选','停用')),
  note text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hardware_catalog (
  id uuid primary key default gen_random_uuid(),
  hardware_name text not null,
  major_category text not null check (major_category in ('铰链','滑轨','拉手','连接件','功能五金','灯带电气','其他')),
  spec text not null default '通用' check (spec in ('全盖(直弯)','半盖(中弯)','内嵌(大弯)','三节轨','托底轨','骑马抽','拉篮','裤架','穿衣镜','上翻支撑','通用')),
  brand text not null default '',
  model text not null default '',
  soft_close boolean not null default false,
  unit text not null check (unit in ('个','副','套','米','张')),
  reference_purchase_price numeric(14,2) not null default 0,
  default_supplier text not null default '',
  status text not null default '在用' check (status in ('在用','备选','停用')),
  note text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.board_bom_items (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  factory_order_id uuid references public.factory_orders(id) on delete set null,
  item_no int not null default 1,
  space text not null default '',
  part_use text not null check (part_use in ('柜体','柜门','见光板','背板','层板','抽屉','其他')),
  board_id uuid references public.board_catalog(id),
  board_name text not null default '',
  brand text not null default '',
  substrate text not null default '',
  thickness_mm numeric(8,2),
  color_name text not null default '',
  finish_process text not null default '',
  pricing_method text not null check (pricing_method in ('按张','按㎡','按延米','按个')),
  unit text not null check (unit in ('张','㎡','延米','个')),
  quantity numeric(14,3) not null default 0,
  reference_unit_price numeric(14,2) not null default 0,
  amount numeric(14,2) generated always as (quantity * reference_unit_price) stored,
  note text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.hardware_bom_items (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  factory_order_id uuid references public.factory_orders(id) on delete set null,
  item_no int not null default 1,
  use_location text not null default '',
  hardware_id uuid references public.hardware_catalog(id),
  hardware_name text not null default '',
  major_category text not null default '',
  spec text not null default '',
  brand text not null default '',
  soft_close boolean not null default false,
  unit text not null check (unit in ('个','副','套','米')),
  quantity numeric(14,3) not null default 0,
  reference_unit_price numeric(14,2) not null default 0,
  amount numeric(14,2) generated always as (case when included_in_base then 0 else quantity * reference_unit_price end) stored,
  included_in_base boolean not null default false,
  note text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.factory_orders
  add column if not exists order_no text,
  add column if not exists business_source text not null default '门店定制',
  add column if not exists order_date date,
  add column if not exists delivery_date date,
  add column if not exists current_process text not null default '未排产',
  add column if not exists board_cost numeric(14,2) not null default 0,
  add column if not exists edge_cost numeric(14,2) not null default 0,
  add column if not exists hardware_cost numeric(14,2) not null default 0,
  add column if not exists processing_labor_cost numeric(14,2) not null default 0,
  add column if not exists outsourcing_cost numeric(14,2) not null default 0,
  add column if not exists other_cost numeric(14,2) not null default 0,
  add column if not exists note text not null default '';

alter table public.factory_orders drop constraint if exists factory_orders_business_source_check;
alter table public.factory_orders add constraint factory_orders_business_source_check check (business_source in ('门店定制','整装配套','外加工'));
alter table public.factory_orders drop constraint if exists factory_orders_current_process_check;
alter table public.factory_orders add constraint factory_orders_current_process_check check (current_process in ('未排产','到货待开料','开料','封边','排钻','加工','试装','打包','安装','已完工'));
alter table public.factory_orders drop constraint if exists factory_orders_status_check;
alter table public.factory_orders add constraint factory_orders_status_check check (status in ('待开工','进行中','暂停','已完工','已结算'));

create unique index if not exists factory_orders_order_no_uq on public.factory_orders(order_no) where order_no is not null;

create table if not exists public.factory_employees (
  id uuid primary key default gen_random_uuid(),
  employee_name text not null,
  job text not null default '',
  pay_method text not null check (pay_method in ('月薪','日薪','计件')),
  pay_rate numeric(14,2),
  employment_status text not null default '在职' check (employment_status in ('在职','离职')),
  note text not null default '',
  auth_user_id uuid references auth.users(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.attendance drop constraint if exists attendance_employee_id_fkey;
alter table public.attendance add constraint attendance_employee_id_fkey foreign key (employee_id) references public.factory_employees(id);
alter table public.attendance
  add column if not exists job text not null default '',
  add column if not exists work_content text not null default '',
  add column if not exists piece_quantity numeric(14,3) not null default 0,
  add column if not exists overtime_hours numeric(8,2) not null default 0,
  add column if not exists recorded_by uuid references auth.users(id);
alter table public.attendance drop constraint if exists attendance_status_check;
alter table public.attendance add constraint attendance_status_check check (status in ('出勤','请假','旷工','加班','休息'));

create table if not exists public.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_date date not null default current_date,
  transaction_type text not null check (transaction_type in ('入库','出库','退料','盘盈','盘亏')),
  material_code text not null,
  material_name text not null,
  category text not null check (category in ('五金','辅料','板材')),
  spec text not null default '',
  unit text not null check (unit in ('个','套','卷','箱','盒','张','米')),
  quantity numeric(14,3) not null default 0,
  unit_price numeric(14,2) not null default 0,
  amount numeric(14,2) generated always as (quantity * unit_price) stored,
  supplier_source text not null default '',
  related_order text not null default '',
  purpose text not null default '',
  handled_by text not null default '',
  note text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.inventory_opening_balances (
  id uuid primary key default gen_random_uuid(),
  material_code text not null unique,
  material_name text not null,
  category text not null check (category in ('五金','辅料','板材')),
  spec text not null default '',
  unit text not null check (unit in ('个','套','卷','箱','盒','张','米')),
  opening_quantity numeric(14,3) not null default 0,
  reference_unit_price numeric(14,2) not null default 0,
  safety_stock numeric(14,3) not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.fixed_costs
  add column if not exists item text not null default '',
  add column if not exists ownership text not null default '共用';
alter table public.fixed_costs drop constraint if exists fixed_costs_category_check;
alter table public.fixed_costs add constraint fixed_costs_category_check check (category in ('房租','水电','固定人工','折旧','办公软件','营销推广','其他'));
alter table public.fixed_costs drop constraint if exists fixed_costs_ownership_check;
alter table public.fixed_costs add constraint fixed_costs_ownership_check check (ownership in ('门店','工厂','共用'));

alter table public.board_catalog enable row level security;
alter table public.hardware_catalog enable row level security;
alter table public.board_bom_items enable row level security;
alter table public.hardware_bom_items enable row level security;
alter table public.factory_employees enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.inventory_opening_balances enable row level security;

create policy board_catalog_access on public.board_catalog for all to authenticated
using (app.role() in ('owner','designer','factory_manager'))
with check (app.role() in ('owner','designer'));
create policy hardware_catalog_access on public.hardware_catalog for all to authenticated
using (app.role() in ('owner','designer','factory_manager'))
with check (app.role() in ('owner','designer'));

create policy board_bom_access on public.board_bom_items for all to authenticated
using (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())) or app.role()='factory_manager')
with check (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())) or app.role()='factory_manager');
create policy hardware_bom_access on public.hardware_bom_items for all to authenticated
using (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())) or app.role()='factory_manager')
with check (app.role()='owner' or (app.role()='designer' and exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())) or app.role()='factory_manager');

create policy factory_employees_owner on public.factory_employees for all to authenticated
using (app.role()='owner') with check (app.role()='owner');
create policy factory_employees_factory_read on public.factory_employees for select to authenticated
using (app.role()='factory_manager');
create policy inventory_transaction_access on public.inventory_transactions for all to authenticated
using (app.role() in ('owner','factory_manager')) with check (app.role() in ('owner','factory_manager'));
create policy inventory_opening_access on public.inventory_opening_balances for all to authenticated
using (app.role() in ('owner','factory_manager')) with check (app.role() in ('owner','factory_manager'));

revoke all on public.board_catalog, public.hardware_catalog, public.board_bom_items, public.hardware_bom_items, public.factory_employees, public.inventory_transactions, public.inventory_opening_balances from anon;
grant select, insert, update, delete on public.board_catalog, public.hardware_catalog, public.board_bom_items, public.hardware_bom_items to authenticated;
grant select on public.factory_employees to authenticated;
grant select, insert, update, delete on public.inventory_transactions, public.inventory_opening_balances to authenticated;
grant insert, update, select on public.attendance, public.factory_orders to authenticated;

create or replace view api.factory_order_detail with (security_invoker=true) as
select id, order_no, customer_id, factory_manager_id, status, business_source, order_date, delivery_date, current_process, note
from public.factory_orders
where app.role() in ('owner','factory_manager')
  and (app.role()='owner' or factory_manager_id=auth.uid());

create or replace view api.owner_factory_finance with (security_invoker=true) as
select id, order_no, customer_id, business_source, order_date, delivery_date, current_process, status,
  order_amount, board_cost, edge_cost, hardware_cost, processing_labor_cost, outsourcing_cost, other_cost,
  (board_cost + edge_cost + hardware_cost + processing_labor_cost + outsourcing_cost + other_cost) as cost_total,
  case when order_amount is null then null else order_amount - (board_cost + edge_cost + hardware_cost + processing_labor_cost + outsourcing_cost + other_cost) end as gross_profit,
  case when order_amount is null or order_amount=0 then null else (order_amount - (board_cost + edge_cost + hardware_cost + processing_labor_cost + outsourcing_cost + other_cost)) / order_amount end as gross_margin,
  note
from public.factory_orders
where app.role()='owner';

create or replace view api.factory_employees_safe with (security_invoker=true) as
select id, employee_name, job, pay_method, employment_status, note, auth_user_id, created_at
from public.factory_employees
where app.role() in ('owner','factory_manager');

create or replace view api.inventory_balance with (security_invoker=true) as
select o.material_code, o.material_name, o.category, o.spec, o.unit, o.opening_quantity,
  coalesce(sum(case when t.transaction_type='入库' then t.quantity else 0 end),0) as current_in,
  coalesce(sum(case when t.transaction_type='出库' then t.quantity else 0 end),0) as current_out,
  o.opening_quantity + coalesce(sum(case when t.transaction_type='入库' then t.quantity else 0 end),0) - coalesce(sum(case when t.transaction_type='出库' then t.quantity else 0 end),0) as ending_quantity,
  o.reference_unit_price,
  (o.opening_quantity + coalesce(sum(case when t.transaction_type='入库' then t.quantity else 0 end),0) - coalesce(sum(case when t.transaction_type='出库' then t.quantity else 0 end),0)) * o.reference_unit_price as ending_amount,
  o.safety_stock,
  case when (o.opening_quantity + coalesce(sum(case when t.transaction_type='入库' then t.quantity else 0 end),0) - coalesce(sum(case when t.transaction_type='出库' then t.quantity else 0 end),0)) <= o.safety_stock then '需补货' else '正常' end as status
from public.inventory_opening_balances o
left join public.inventory_transactions t on t.material_code=o.material_code
where app.role() in ('owner','factory_manager')
group by o.material_code,o.material_name,o.category,o.spec,o.unit,o.opening_quantity,o.reference_unit_price,o.safety_stock;

create or replace view api.owner_monthly_net_profit with (security_invoker=true) as
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

grant select on api.factory_order_detail, api.owner_factory_finance, api.factory_employees_safe, api.inventory_balance, api.owner_monthly_net_profit to authenticated;

create index if not exists board_bom_customer_idx on public.board_bom_items(customer_id);
create index if not exists hardware_bom_customer_idx on public.hardware_bom_items(customer_id);
create index if not exists inventory_transactions_material_idx on public.inventory_transactions(material_code);
create index if not exists attendance_work_date_idx on public.attendance(work_date);
create index if not exists fixed_costs_month_idx on public.fixed_costs(cost_month);
