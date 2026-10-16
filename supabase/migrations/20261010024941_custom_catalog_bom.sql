-- Phase 1, checkpoint 1. Custom objects only; no Auth/account/renovation changes.
-- API views run as a dedicated NOLOGIN, NOBYPASSRLS owner. The owner is
-- FORCE-RLS constrained, while each projection helper also applies a fixed
-- role and customer/order ownership check before returning whitelisted fields.
begin;
create schema if not exists custom_private;
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anju_custom_executor') then
    create role anju_custom_executor nologin noinherit nosuperuser nobypassrls;
  end if;
end $$;
grant anju_custom_executor to postgres;
grant usage on schema public,app,api,auth,custom_private to anju_custom_executor;
grant usage,create on schema custom_private to anju_custom_executor;
grant usage on schema custom_private,api to authenticated;
grant usage on schema auth to postgres, authenticated;
grant usage,create on schema api to anju_custom_executor;
revoke all on schema custom_private from public,anon;

alter table public.board_catalog add column if not exists default_sales_price numeric(14,2);
alter table public.hardware_catalog add column if not exists default_sales_price numeric(14,2);
alter table public.board_bom_items
 add column if not exists quote_id uuid references public.quotes(id),
 add column if not exists source_item_id uuid references public.board_bom_items(id),
 add column if not exists color_code text not null default '',
 add column if not exists eco_grade text not null default '',
 add column if not exists edge_process text not null default '无',
 add column if not exists standard_size text not null default '',
 add column if not exists sales_unit_price numeric(14,2) not null default 0,
 add column if not exists sales_amount numeric(14,2) generated always as (quantity*sales_unit_price) stored,
 add column if not exists reference_purchase_price_snapshot numeric(14,2),
 add column if not exists edge_length_m numeric(14,3) not null default 0,
 add column if not exists edge_charge_mode text not null default 'included',
 add column if not exists edge_sales_price_per_meter_snapshot numeric(14,2) not null default 0,
 add column if not exists edge_sales_amount numeric(14,2) generated always as (case when edge_charge_mode='separate' then edge_length_m*edge_sales_price_per_meter_snapshot else 0 end) stored,
 add column if not exists utilization_rate numeric(5,4) not null default 1,
 add column if not exists linear_width_mm numeric(10,2),
 add column if not exists updated_at timestamptz not null default now();
alter table public.board_bom_items drop constraint if exists board_bom_items_unit_check;
alter table public.board_bom_items add constraint board_bom_items_unit_check check(unit in ('张','㎡','延米','个','米'));
alter table public.board_bom_items drop constraint if exists custom_board_bom_valid;
alter table public.board_bom_items add constraint custom_board_bom_valid check(
 quantity>=0 and sales_unit_price>=0 and edge_length_m>=0 and edge_sales_price_per_meter_snapshot>=0
 and edge_charge_mode in ('included','separate') and edge_process in ('EVA','PUR','激光','无')
 and utilization_rate>0 and utilization_rate<=1 and (linear_width_mm is null or linear_width_mm>0));
alter table public.hardware_bom_items
 add column if not exists quote_id uuid references public.quotes(id),
 add column if not exists source_item_id uuid references public.hardware_bom_items(id),
 add column if not exists model text not null default '',
 add column if not exists sales_unit_price numeric(14,2) not null default 0,
 add column if not exists sales_amount numeric(14,2) generated always as (case when included_in_base then 0 else quantity*sales_unit_price end) stored,
 add column if not exists reference_purchase_price_snapshot numeric(14,2),
 add column if not exists updated_at timestamptz not null default now();
alter table public.hardware_bom_items drop constraint if exists custom_hardware_bom_valid;
alter table public.hardware_bom_items add constraint custom_hardware_bom_valid check(quantity>=0 and sales_unit_price>=0);
alter table public.factory_orders add column if not exists custom_quote_id uuid references public.quotes(id);
create unique index if not exists custom_order_quote_unique on public.factory_orders(custom_quote_id) where custom_quote_id is not null;
create index if not exists custom_board_quote_idx on public.board_bom_items(quote_id);
create index if not exists custom_hardware_quote_idx on public.hardware_bom_items(quote_id);
create index if not exists custom_board_order_idx on public.board_bom_items(factory_order_id);
create index if not exists custom_hardware_order_idx on public.hardware_bom_items(factory_order_id);

create table if not exists public.custom_catalog_price_history(
 id uuid primary key default gen_random_uuid(), catalog_kind text not null check(catalog_kind in ('board','hardware')),
 catalog_id uuid not null, reference_purchase_price numeric(14,2),default_sales_price numeric(14,2),
 changed_by uuid not null references auth.users(id),changed_at timestamptz not null default now(),note text not null default '');
create index if not exists custom_price_catalog_idx on public.custom_catalog_price_history(catalog_kind,catalog_id,changed_at desc);
create table if not exists public.edge_process_rates(
 id uuid primary key default gen_random_uuid(),edge_process text not null check(edge_process in ('EVA','PUR','激光')),
 processing_mode text not null check(processing_mode in ('本厂','外协')),sales_price_per_meter numeric(14,2) not null check(sales_price_per_meter>=0),
 cost_per_meter numeric(14,2) not null check(cost_per_meter>=0),effective_from date not null,effective_to date,
 changed_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check(effective_to is null or effective_to>=effective_from),unique(edge_process,processing_mode,effective_from));
create table if not exists public.custom_purchase_orders(
 id uuid primary key default gen_random_uuid(),supplier text not null,bill_no text not null default '',purchase_date date not null,
 status text not null default '待核对' check(status in ('待核对','已核对','已入库','已付款')),
 freight numeric(14,2) not null default 0 check(freight>=0),discount numeric(14,2) not null default 0 check(discount>=0),
 note text not null default '',created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 checked_at timestamptz,stocked_at timestamptz,paid_at timestamptz);
create table if not exists public.custom_purchase_lines(
 id uuid primary key default gen_random_uuid(),purchase_order_id uuid not null references public.custom_purchase_orders(id),
 board_id uuid references public.board_catalog(id),hardware_id uuid references public.hardware_catalog(id),
 temporary_item boolean not null default false,item_name text not null,brand text not null default '',spec text not null default '',
 catalog_snapshot jsonb not null default '{}',unit text not null check(unit in ('张','㎡','延米','个','米','副','套')),
 quantity numeric(14,3) not null check(quantity>0),purchase_unit_price numeric(14,2) not null check(purchase_unit_price>=0),
 line_amount numeric(14,2) generated always as (round(quantity*purchase_unit_price,2)) stored,
 declared_amount numeric(14,2) not null check(declared_amount>=0),note text not null default '',
 check(num_nonnulls(board_id,hardware_id)<=1),check(temporary_item or num_nonnulls(board_id,hardware_id)=1));
create table if not exists public.custom_purchase_allocations(
 id uuid primary key default gen_random_uuid(),purchase_line_id uuid not null references public.custom_purchase_lines(id),
 factory_order_id uuid not null references public.factory_orders(id),allocated_quantity numeric(14,3) not null check(allocated_quantity>0),
 allocation_method text not null check(allocation_method in ('按BOM','手工')),allocated_amount numeric(14,2),
 unique(purchase_line_id,factory_order_id));
create table if not exists public.custom_inventory_balances(
 catalog_kind text not null check(catalog_kind in ('board','hardware')),catalog_id uuid not null,
 unit text not null,quantity numeric(14,3) not null default 0 check(quantity>=0),
 average_unit_cost numeric(18,6) not null default 0 check(average_unit_cost>=0),updated_at timestamptz not null default now(),
 primary key(catalog_kind,catalog_id,unit));
create table if not exists public.custom_inventory_transactions(
 id uuid primary key default gen_random_uuid(),catalog_kind text not null check(catalog_kind in ('board','hardware')),catalog_id uuid not null,
 transaction_type text not null check(transaction_type in ('入库','领料','退料','盘点')),transaction_date date not null default current_date,
 quantity numeric(14,3) not null check(quantity>0),unit text not null,factory_order_id uuid references public.factory_orders(id),
 purchase_line_id uuid references public.custom_purchase_lines(id),source_transaction_id uuid references public.custom_inventory_transactions(id),
 unit_cost numeric(18,6) not null,total_cost numeric(14,2) not null,created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),note text not null default '',request_id uuid unique);
create unique index if not exists custom_purchase_receipt_unique on public.custom_inventory_transactions(purchase_line_id) where transaction_type='入库';
create index if not exists custom_inventory_source_idx on public.custom_inventory_transactions(source_transaction_id);
create table if not exists public.custom_cost_entries(
 id uuid primary key default gen_random_uuid(),factory_order_id uuid not null references public.factory_orders(id),
 category text not null check(category in ('板材','封边','五金','人工','安装','外协','其他')),occurred_at date not null default current_date,
 quantity numeric(14,3) not null,unit text not null,unit_cost numeric(18,6) not null,amount numeric(14,2) not null,
 source_transaction_id uuid unique references public.custom_inventory_transactions(id),edge_rate_id uuid references public.edge_process_rates(id),
 note text not null default '',created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),request_id uuid unique);
create index if not exists custom_cost_order_idx on public.custom_cost_entries(factory_order_id,occurred_at);
create table if not exists public.custom_attachments(
 id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.customers(id),quote_id uuid references public.quotes(id),
 factory_order_id uuid references public.factory_orders(id),purchase_order_id uuid references public.custom_purchase_orders(id),
 node_date date not null,document_kind text not null check(document_kind in ('quote','order','purchase','expense')),
 storage_path text not null unique,file_name text not null,mime_type text not null,file_size bigint not null check(file_size>0 and file_size<=20971520),
 uploaded_by uuid not null references auth.users(id),created_at timestamptz not null default now());
create index if not exists custom_attachment_customer_idx on public.custom_attachments(customer_id,document_kind);
create index if not exists custom_purchase_line_order_idx on public.custom_purchase_lines(purchase_order_id);

-- All custom helpers are owned by a role without BYPASSRLS. These lookups also
-- deliberately restrict the existing shared customer/quote/order tables to custom.
create or replace function custom_private.request_uid() returns uuid
language sql stable security definer set search_path='' as $$
  select auth.uid()
$$;
alter function custom_private.request_uid() owner to postgres;
create or replace function custom_private.request_role() returns text
language sql stable security definer set search_path='' as $$
  select coalesce(auth.jwt()->'app_metadata'->>'role','')
$$;
alter function custom_private.request_role() owner to postgres;
grant execute on function custom_private.request_uid(), custom_private.request_role() to anju_custom_executor;
-- Keep shared RLS role checks callable under the non-bypass executor without
-- resolving auth.jwt() as that executor.
create or replace function app.role() returns text
language sql stable security definer set search_path='' as $$
  select custom_private.request_role()
$$;
alter function app.role() owner to postgres;
grant execute on function app.role() to authenticated, anju_custom_executor;
create or replace function custom_private.is_factory_manager(p_uid uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from auth.users u where u.id=p_uid and u.raw_app_meta_data->>'role'='factory_manager')
$$;
alter function custom_private.is_factory_manager(uuid) owner to postgres;
grant execute on function custom_private.is_factory_manager(uuid) to anju_custom_executor;
create or replace function custom_private.require_roles(p_roles text[]) returns boolean
language plpgsql stable security definer set search_path='' as $$
begin
 if custom_private.request_uid() is null or not coalesce(custom_private.request_role()=any(p_roles),false) then raise exception using errcode='42501',message='custom_forbidden';end if;
 return true;
end $$;
create or replace function custom_private.customer_allowed(p_customer_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.customers c where c.id=p_customer_id and c.business_line='custom'
 and (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and c.owner_id=custom_private.request_uid())))
$$;
create or replace function custom_private.order_allowed(p_order_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.factory_orders o where o.id=p_order_id and o.custom_quote_id is not null
 and (custom_private.request_role()='owner' or (custom_private.request_role()='factory_manager' and o.factory_manager_id=custom_private.request_uid())))
$$;
create or replace function custom_private.quote_allowed(p_quote_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.quotes q where q.id=p_quote_id and q.business_line='custom' and custom_private.customer_allowed(q.customer_id))
$$;
drop policy if exists custom_executor_customers on public.customers;
create policy custom_executor_customers on public.customers for select to anju_custom_executor
 using(business_line='custom' and (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and owner_id=custom_private.request_uid())));
drop policy if exists custom_executor_quotes on public.quotes;
create policy custom_executor_quotes on public.quotes for all to anju_custom_executor
 using(business_line='custom' and custom_private.customer_allowed(customer_id))
 with check(business_line='custom' and custom_private.customer_allowed(customer_id));
drop policy if exists custom_executor_orders on public.factory_orders;
create policy custom_executor_orders on public.factory_orders for all to anju_custom_executor
 using(custom_quote_id is not null and (custom_private.request_role()='owner' or (custom_private.request_role()='factory_manager' and factory_manager_id=custom_private.request_uid())))
 with check(custom_quote_id is not null and (custom_private.request_role()='owner' or (custom_private.request_role()='factory_manager' and factory_manager_id=custom_private.request_uid())));
grant select on public.customers to anju_custom_executor;
grant select,insert,update on public.quotes,public.factory_orders to anju_custom_executor;
grant select(id,raw_app_meta_data) on auth.users to anju_custom_executor;
grant execute on function app.role(),auth.uid(),auth.jwt() to anju_custom_executor;

-- Replace only the four custom catalog/BOM policies; original account and
-- renovation policies remain intact. No shared-role raw-table grants remain.
do $$ declare t text;p record;columns_sql text; begin
 foreach t in array array['board_catalog','hardware_catalog','board_bom_items','hardware_bom_items',
 'custom_catalog_price_history','edge_process_rates','custom_purchase_orders','custom_purchase_lines','custom_purchase_allocations',
 'custom_inventory_balances','custom_inventory_transactions','custom_cost_entries','custom_attachments'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('alter table public.%I force row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 select string_agg(quote_ident(attname),',') into columns_sql from pg_attribute where attrelid=to_regclass('public.'||t) and attnum>0 and not attisdropped;
 execute format('revoke select(%s),insert(%s),update(%s),references(%s) on public.%I from public,anon,authenticated',columns_sql,columns_sql,columns_sql,columns_sql,t);
 execute format('grant select,insert,update,delete on public.%I to anju_custom_executor',t);
 for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
 execute format('drop policy %I on public.%I',p.policyname,t); end loop;
 end loop;
end $$;
create policy custom_catalog_access on public.board_catalog for all to anju_custom_executor
 using(custom_private.request_role() in ('owner','designer','factory_manager')) with check(custom_private.request_role() in ('owner','designer')); 
create policy custom_catalog_access on public.hardware_catalog for all to anju_custom_executor
 using(custom_private.request_role() in ('owner','designer','factory_manager')) with check(custom_private.request_role() in ('owner','designer')); 
create policy custom_board_access on public.board_bom_items for all to anju_custom_executor
 using((quote_id is not null and factory_order_id is null and custom_private.quote_allowed(quote_id))
 or (factory_order_id is not null and custom_private.order_allowed(factory_order_id)))
 with check((quote_id is not null and factory_order_id is null and custom_private.quote_allowed(quote_id))
 or (factory_order_id is not null and custom_private.order_allowed(factory_order_id)));
create policy custom_hardware_access on public.hardware_bom_items for all to anju_custom_executor
 using((quote_id is not null and factory_order_id is null and custom_private.quote_allowed(quote_id))
 or (factory_order_id is not null and custom_private.order_allowed(factory_order_id)))
 with check((quote_id is not null and factory_order_id is null and custom_private.quote_allowed(quote_id))
 or (factory_order_id is not null and custom_private.order_allowed(factory_order_id)));
create policy custom_cost_select on public.custom_cost_entries for select to anju_custom_executor using(app.role()='owner');
create policy custom_cost_insert on public.custom_cost_entries for insert to anju_custom_executor
 with check(custom_private.order_allowed(factory_order_id) and created_by=(select auth.uid()));
create policy custom_attachment_access on public.custom_attachments for all to anju_custom_executor
 using((app.role()='owner' or (app.role()='designer' and document_kind in ('quote','order') and custom_private.customer_allowed(customer_id)))
 or (app.role()='factory_manager' and document_kind='expense' and uploaded_by=(select auth.uid()) and custom_private.order_allowed(factory_order_id)))
 with check((app.role()='owner' and custom_private.customer_allowed(customer_id))
 or (app.role()='designer' and document_kind in ('quote','order') and custom_private.customer_allowed(customer_id))
 or (app.role()='factory_manager' and document_kind='expense' and uploaded_by=(select auth.uid()) and custom_private.order_allowed(factory_order_id)));
create policy custom_edge_access on public.edge_process_rates for all to anju_custom_executor
 using(app.role() in ('owner','designer','factory_manager')) with check(app.role()='owner');
do $$ declare t text;begin
 foreach t in array array['custom_catalog_price_history','custom_purchase_orders','custom_purchase_lines','custom_purchase_allocations',
 'custom_inventory_balances','custom_inventory_transactions'] loop
 execute format('create policy custom_owner_access on public.%I for all to anju_custom_executor using (app.role()=''owner'') with check (app.role()=''owner'')',t);
 end loop;
end $$;

-- Further API and transaction functions below. Ownership/grants finalized last.
-- Static projection contracts: no SELECT * over a mixed-price table.
drop view if exists api.custom_order_bom_factory;
drop function if exists custom_private.read_custom_order_bom_factory();
do $$ declare r record;begin
 for r in select * from (values
 ('custom_board_catalog_sales','owner,designer',
 'id uuid,material_name text,category_use text,brand text,substrate text,thickness_mm numeric,color_name text,color_code text,finish_process text,eco_grade text,edge_process text,standard_size text,pricing_method text,default_supplier text,status text,note text,default_sales_price numeric',
 'select b.id,b.material_name,b.category_use,b.brand,b.substrate,b.thickness_mm,b.color_name,b.color_code,b.finish_process,b.eco_grade,b.edge_process,b.standard_size,b.pricing_method,b.default_supplier,b.status,b.note,b.default_sales_price from public.board_catalog b'),
 ('custom_hardware_catalog_sales','owner,designer',
 'id uuid,hardware_name text,major_category text,spec text,brand text,model text,soft_close boolean,unit text,default_supplier text,status text,note text,default_sales_price numeric',
 'select h.id,h.hardware_name,h.major_category,h.spec,h.brand,h.model,h.soft_close,h.unit,h.default_supplier,h.status,h.note,h.default_sales_price from public.hardware_catalog h'),
 ('owner_custom_catalog_prices','owner',
 'catalog_kind text,catalog_id uuid,reference_purchase_price numeric,default_sales_price numeric',
 'select ''board''::text,b.id,b.reference_purchase_price,b.default_sales_price from public.board_catalog b union all select ''hardware''::text,h.id,h.reference_purchase_price,h.default_sales_price from public.hardware_catalog h'),
 ('owner_custom_price_history','owner',
 'id uuid,catalog_kind text,catalog_id uuid,reference_purchase_price numeric,default_sales_price numeric,changed_by uuid,changed_at timestamptz,note text',
 'select h.id,h.catalog_kind,h.catalog_id,h.reference_purchase_price,h.default_sales_price,h.changed_by,h.changed_at,h.note from public.custom_catalog_price_history h'),
 ('custom_edge_rates_sales','owner,designer',
 'id uuid,edge_process text,processing_mode text,sales_price_per_meter numeric,effective_from date,effective_to date',
 'select r.id,r.edge_process,r.processing_mode,r.sales_price_per_meter,r.effective_from,r.effective_to from public.edge_process_rates r'),
 ('owner_custom_edge_rates','owner',
 'id uuid,edge_process text,processing_mode text,sales_price_per_meter numeric,cost_per_meter numeric,effective_from date,effective_to date',
 'select r.id,r.edge_process,r.processing_mode,r.sales_price_per_meter,r.cost_per_meter,r.effective_from,r.effective_to from public.edge_process_rates r'),
 ('custom_quote_board_items','owner,designer',
 'id uuid,quote_id uuid,customer_id uuid,item_no integer,space text,part_use text,board_id uuid,board_name text,brand text,substrate text,thickness_mm numeric,color_name text,color_code text,finish_process text,eco_grade text,edge_process text,standard_size text,pricing_method text,unit text,quantity numeric,sales_unit_price numeric,sales_amount numeric,edge_length_m numeric,edge_charge_mode text,edge_sales_price_per_meter_snapshot numeric,edge_sales_amount numeric,utilization_rate numeric,linear_width_mm numeric,note text',
 'select b.id,b.quote_id,b.customer_id,b.item_no,b.space,b.part_use,b.board_id,b.board_name,b.brand,b.substrate,b.thickness_mm,b.color_name,b.color_code,b.finish_process,b.eco_grade,b.edge_process,b.standard_size,b.pricing_method,b.unit,b.quantity,b.sales_unit_price,b.sales_amount,b.edge_length_m,b.edge_charge_mode,b.edge_sales_price_per_meter_snapshot,b.edge_sales_amount,b.utilization_rate,b.linear_width_mm,b.note from public.board_bom_items b where b.factory_order_id is null and b.quote_id is not null'),
 ('custom_quote_hardware_items','owner,designer',
 'id uuid,quote_id uuid,customer_id uuid,item_no integer,use_location text,hardware_id uuid,hardware_name text,major_category text,spec text,brand text,model text,soft_close boolean,unit text,quantity numeric,included_in_base boolean,sales_unit_price numeric,sales_amount numeric,note text',
 'select h.id,h.quote_id,h.customer_id,h.item_no,h.use_location,h.hardware_id,h.hardware_name,h.major_category,h.spec,h.brand,h.model,h.soft_close,h.unit,h.quantity,h.included_in_base,h.sales_unit_price,h.sales_amount,h.note from public.hardware_bom_items h where h.factory_order_id is null and h.quote_id is not null'),
 ('custom_order_bom_factory','owner,factory_manager',
 'item_kind text,id uuid,factory_order_id uuid,source_item_id uuid,customer_id uuid,catalog_id uuid,item_name text,brand text,unit text,quantity numeric,thickness_mm numeric,color_name text,color_code text,finish_process text,edge_process text,edge_length_m numeric,space text,part_use text',
 'select ''board''::text,b.id,b.factory_order_id,b.source_item_id,b.customer_id,b.board_id,b.board_name,b.brand,b.unit,b.quantity,b.thickness_mm,b.color_name,b.color_code,b.finish_process,b.edge_process,b.edge_length_m,b.space,b.part_use from public.board_bom_items b where b.factory_order_id is not null union all select ''hardware''::text,h.id,h.factory_order_id,h.source_item_id,h.customer_id,h.hardware_id,h.hardware_name,h.brand,h.unit,h.quantity,null::numeric,''''::text,''''::text,''''::text,''无''::text,0::numeric,h.use_location,h.spec from public.hardware_bom_items h where h.factory_order_id is not null'),
 ('owner_custom_cost_ledger','owner',
 'id uuid,factory_order_id uuid,category text,occurred_at date,quantity numeric,unit text,unit_cost numeric,amount numeric,source_transaction_id uuid,edge_rate_id uuid,note text,created_by uuid',
 'select c.id,c.factory_order_id,c.category,c.occurred_at,c.quantity,c.unit,c.unit_cost,c.amount,c.source_transaction_id,c.edge_rate_id,c.note,c.created_by from public.custom_cost_entries c'),
 ('custom_purchase_review','owner',
 'id uuid,supplier text,bill_no text,purchase_date date,status text,freight numeric,discount numeric,note text,checked_at timestamptz,stocked_at timestamptz,paid_at timestamptz',
 'select p.id,p.supplier,p.bill_no,p.purchase_date,p.status,p.freight,p.discount,p.note,p.checked_at,p.stocked_at,p.paid_at from public.custom_purchase_orders p'),
 ('owner_custom_purchase_lines','owner',
 'id uuid,purchase_order_id uuid,board_id uuid,hardware_id uuid,temporary_item boolean,item_name text,brand text,spec text,catalog_snapshot jsonb,unit text,quantity numeric,purchase_unit_price numeric,line_amount numeric,declared_amount numeric,amount_mismatch boolean,note text',
 'select l.id,l.purchase_order_id,l.board_id,l.hardware_id,l.temporary_item,l.item_name,l.brand,l.spec,l.catalog_snapshot,l.unit,l.quantity,l.purchase_unit_price,l.line_amount,l.declared_amount,l.line_amount<>l.declared_amount,l.note from public.custom_purchase_lines l'),
 ('owner_custom_inventory_balance','owner',
 'catalog_kind text,catalog_id uuid,unit text,quantity numeric,average_unit_cost numeric,updated_at timestamptz',
 'select b.catalog_kind,b.catalog_id,b.unit,b.quantity,b.average_unit_cost,b.updated_at from public.custom_inventory_balances b'),
 ('owner_custom_purchase_allocations','owner',
 'id uuid,purchase_line_id uuid,factory_order_id uuid,allocated_quantity numeric,allocation_method text,allocated_amount numeric',
 'select a.id,a.purchase_line_id,a.factory_order_id,a.allocated_quantity,a.allocation_method,a.allocated_amount from public.custom_purchase_allocations a'),
 ('custom_inventory_quantities','owner,factory_manager',
 'catalog_kind text,catalog_id uuid,unit text,quantity numeric,updated_at timestamptz',
 'select b.catalog_kind,b.catalog_id,b.unit,b.quantity,b.updated_at from public.custom_inventory_balances b'),
 ('custom_material_transactions','owner,factory_manager',
 'id uuid,catalog_kind text,catalog_id uuid,transaction_type text,transaction_date date,quantity numeric,unit text,factory_order_id uuid,source_transaction_id uuid',
 'select t.id,t.catalog_kind,t.catalog_id,t.transaction_type,t.transaction_date,t.quantity,t.unit,t.factory_order_id,t.source_transaction_id from public.custom_inventory_transactions t'),
 ('custom_attachments','owner,designer',
 'id uuid,customer_id uuid,quote_id uuid,factory_order_id uuid,purchase_order_id uuid,node_date date,document_kind text,storage_path text,file_name text,mime_type text,file_size bigint',
 'select a.id,a.customer_id,a.quote_id,a.factory_order_id,a.purchase_order_id,a.node_date,a.document_kind,a.storage_path,a.file_name,a.mime_type,a.file_size from public.custom_attachments a')
 ) as surfaces(name,roles,cols,query) loop
 execute format('create or replace function custom_private.read_%I() returns table(%s) language plpgsql stable security definer set search_path='''' as $fn$ begin perform custom_private.require_roles(string_to_array(%L,'','')); return query %s; end $fn$',r.name,r.cols,r.roles,r.query);
 execute format('create or replace view api.%I with(security_invoker=false) as select * from custom_private.read_%I()',r.name,r.name);
 execute format('alter view api.%I owner to anju_custom_executor',r.name);
 execute format('alter view api.%I owner to anju_custom_executor',r.name);
 execute format('revoke all on api.%I from public,anon; grant select on api.%I to authenticated',r.name,r.name);
 end loop;
end $$;
create or replace function custom_private.read_owner_custom_order_profit()
returns table(factory_order_id uuid,customer_id uuid,sales_amount numeric,board_cost numeric,edge_cost numeric,hardware_cost numeric,labor_cost numeric,installation_outsourcing_cost numeric,other_cost numeric,cost_total numeric,gross_profit numeric,gross_margin numeric)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query select o.id,o.customer_id,o.order_amount,
 coalesce(sum(c.amount) filter(where c.category='板材'),0),coalesce(sum(c.amount) filter(where c.category='封边'),0),
 coalesce(sum(c.amount) filter(where c.category='五金'),0),coalesce(sum(c.amount) filter(where c.category='人工'),0),
 coalesce(sum(c.amount) filter(where c.category in ('安装','外协')),0),coalesce(sum(c.amount) filter(where c.category='其他'),0),
 coalesce(sum(c.amount),0),o.order_amount-coalesce(sum(c.amount),0),
 case when o.order_amount=0 then null::numeric else (o.order_amount-coalesce(sum(c.amount),0))/o.order_amount end
 from public.factory_orders o left join public.custom_cost_entries c on c.factory_order_id=o.id
 where o.custom_quote_id is not null group by o.id,o.customer_id,o.order_amount;
end $$;
create or replace view api.owner_custom_order_profit with(security_invoker=false) as select * from custom_private.read_owner_custom_order_profit();
alter view api.owner_custom_order_profit owner to anju_custom_executor;
revoke all on api.owner_custom_order_profit from public,anon;grant select on api.owner_custom_order_profit to authenticated;

create or replace function custom_private.validate_keys(p_data jsonb,p_keys text[]) returns void
language plpgsql immutable security invoker set search_path='' as $$
begin
 if jsonb_typeof(p_data)<>'object' then raise exception using errcode='22023',message='custom_payload_must_be_object';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where not(k=any(p_keys))) then
 raise exception using errcode='42501',message='custom_disallowed_field';end if;
end $$;
create or replace function custom_private.save_catalog(p_kind text,p_data jsonb,p_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b public.board_catalog%rowtype;h public.hardware_catalog%rowtype;out_id uuid; old_purchase numeric;old_sales numeric; new_purchase numeric;new_sales numeric;
begin
 perform custom_private.require_roles(array['owner','designer']);
 if app.role()<>'owner' and p_data ? 'reference_purchase_price' then raise exception using errcode='42501',message='custom_owner_price_only';end if;
 if p_kind='board' then
 perform custom_private.validate_keys(p_data,array['material_name','category_use','brand','substrate','thickness_mm','color_name','color_code','finish_process','eco_grade','edge_process','standard_size','pricing_method','default_supplier','status','note','reference_purchase_price','default_sales_price']);
 if p_id is not null then select * into b from public.board_catalog where id=p_id for update;if not found then raise exception using errcode='42501',message='custom_not_found_or_forbidden';end if;
 old_purchase=b.reference_purchase_price;old_sales=b.default_sales_price;
 else b.id=gen_random_uuid();b.brand='';b.thickness_mm=18;b.color_name='';b.color_code='';b.standard_size='';b.reference_purchase_price=0;b.default_supplier='';b.status='在用';b.note='';b.created_by=auth.uid();b.created_at=now();end if;
 b=jsonb_populate_record(b,p_data); b.updated_at=now();
 insert into public.board_catalog(id,material_name,category_use,brand,substrate,thickness_mm,color_name,color_code,finish_process,eco_grade,edge_process,standard_size,pricing_method,reference_purchase_price,default_sales_price,default_supplier,status,note,created_by,created_at,updated_at)
 values(b.id,b.material_name,b.category_use,b.brand,b.substrate,b.thickness_mm,b.color_name,b.color_code,b.finish_process,b.eco_grade,b.edge_process,b.standard_size,b.pricing_method,b.reference_purchase_price,b.default_sales_price,b.default_supplier,b.status,b.note,b.created_by,b.created_at,b.updated_at)
 on conflict(id) do update set material_name=excluded.material_name,category_use=excluded.category_use,brand=excluded.brand,substrate=excluded.substrate,thickness_mm=excluded.thickness_mm,color_name=excluded.color_name,color_code=excluded.color_code,finish_process=excluded.finish_process,eco_grade=excluded.eco_grade,edge_process=excluded.edge_process,standard_size=excluded.standard_size,pricing_method=excluded.pricing_method,reference_purchase_price=excluded.reference_purchase_price,default_sales_price=excluded.default_sales_price,default_supplier=excluded.default_supplier,status=excluded.status,note=excluded.note,updated_at=excluded.updated_at;
 out_id=b.id;new_purchase=b.reference_purchase_price;new_sales=b.default_sales_price;
 elsif p_kind='hardware' then
 perform custom_private.validate_keys(p_data,array['hardware_name','major_category','spec','brand','model','soft_close','unit','default_supplier','status','note','reference_purchase_price','default_sales_price']);
 if p_id is not null then select * into h from public.hardware_catalog where id=p_id for update;if not found then raise exception using errcode='42501',message='custom_not_found_or_forbidden';end if;
 old_purchase=h.reference_purchase_price;old_sales=h.default_sales_price;
 else h.id=gen_random_uuid();h.brand='';h.model='';h.spec='通用';h.soft_close=false;h.reference_purchase_price=0;h.default_supplier='';h.status='在用';h.note='';h.created_by=auth.uid();h.created_at=now();end if;
 h=jsonb_populate_record(h,p_data);h.updated_at=now();
 insert into public.hardware_catalog(id,hardware_name,major_category,spec,brand,model,soft_close,unit,reference_purchase_price,default_sales_price,default_supplier,status,note,created_by,created_at,updated_at)
 values(h.id,h.hardware_name,h.major_category,h.spec,h.brand,h.model,h.soft_close,h.unit,h.reference_purchase_price,h.default_sales_price,h.default_supplier,h.status,h.note,h.created_by,h.created_at,h.updated_at)
 on conflict(id) do update set hardware_name=excluded.hardware_name,major_category=excluded.major_category,spec=excluded.spec,brand=excluded.brand,model=excluded.model,soft_close=excluded.soft_close,unit=excluded.unit,reference_purchase_price=excluded.reference_purchase_price,default_sales_price=excluded.default_sales_price,default_supplier=excluded.default_supplier,status=excluded.status,note=excluded.note,updated_at=excluded.updated_at;
 out_id=h.id;new_purchase=h.reference_purchase_price;new_sales=h.default_sales_price;
 else raise exception using errcode='22023',message='custom_invalid_catalog_kind';end if;
 if new_purchase<0 or new_sales<0 then raise exception using errcode='23514',message='custom_negative_price';end if;
 if p_id is null or old_purchase is distinct from new_purchase or old_sales is distinct from new_sales then
 insert into public.custom_catalog_price_history(catalog_kind,catalog_id,reference_purchase_price,default_sales_price,changed_by)
 values(p_kind,out_id,new_purchase,new_sales,auth.uid());end if;
 return jsonb_build_object('id',out_id,'status','saved');
end $$;
drop policy if exists custom_owner_access on public.custom_catalog_price_history;
create policy custom_history_read on public.custom_catalog_price_history for select to anju_custom_executor using(app.role()='owner');
create policy custom_history_insert on public.custom_catalog_price_history for insert to anju_custom_executor
 with check(app.role() in ('owner','designer') and changed_by=(select auth.uid()));

create or replace function custom_private.create_quote(p_customer_id uuid,p_title text) returns jsonb
language plpgsql security definer set search_path='' as $$ declare out_id uuid=gen_random_uuid();begin
 perform custom_private.require_roles(array['owner','designer']);
 if not custom_private.customer_allowed(p_customer_id) then raise exception using errcode='42501',message='custom_customer_forbidden';end if;
 insert into public.quotes(id,customer_id,business_line,title,created_by) values(out_id,p_customer_id,'custom',p_title,auth.uid());
 return jsonb_build_object('id',out_id,'status','draft');end $$;

create or replace function custom_private.save_bom(p_quote_id uuid,p_kind text,p_data jsonb,p_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare q public.quotes%rowtype;b public.board_bom_items%rowtype;h public.hardware_bom_items%rowtype; bc public.board_catalog%rowtype;hc public.hardware_catalog%rowtype;out_id uuid;
begin
 perform custom_private.require_roles(array['owner','designer']);
 select * into q from public.quotes where id=p_quote_id and business_line='custom' for update;
 if not found or not custom_private.quote_allowed(q.id) then raise exception using errcode='42501',message='custom_quote_forbidden';end if;
 if q.status<>'draft' then raise exception using errcode='22023',message='custom_quote_locked';end if;
 if p_kind='board' then
 perform custom_private.validate_keys(p_data,array['item_no','space','part_use','board_id','board_name','brand','substrate','thickness_mm','color_name','color_code','finish_process','eco_grade','edge_process','standard_size','pricing_method','unit','quantity','sales_unit_price','edge_length_m','edge_charge_mode','edge_sales_price_per_meter_snapshot','utilization_rate','linear_width_mm','note']);
 if p_id is not null then select * into b from public.board_bom_items where id=p_id and quote_id=p_quote_id and factory_order_id is null;
 if not found then raise exception using errcode='42501',message='custom_item_forbidden';end if;
 else b.id=gen_random_uuid();b.item_no=1;b.space='';b.part_use='其他';b.board_name='';b.brand='';b.substrate='';b.color_name='';b.color_code='';b.finish_process='';b.eco_grade='';b.edge_process='无';b.standard_size='';b.pricing_method='按张';b.unit='张';b.quantity=0;b.sales_unit_price=0;b.edge_length_m=0;b.edge_charge_mode='included';b.edge_sales_price_per_meter_snapshot=0;b.utilization_rate=1;b.note='';b.created_at=now();b.created_by=auth.uid();end if;
 if p_data ? 'board_id' and nullif(p_data->>'board_id','') is not null then
 select * into bc from public.board_catalog where id=(p_data->>'board_id')::uuid and status<>'停用';
 if not found then raise exception using errcode='22023',message='custom_catalog_unavailable';end if;
 b.board_id=bc.id;b.board_name=bc.material_name;b.brand=bc.brand;b.substrate=bc.substrate;b.thickness_mm=bc.thickness_mm;b.color_name=bc.color_name;b.color_code=bc.color_code;b.finish_process=bc.finish_process;b.eco_grade=bc.eco_grade;b.edge_process=bc.edge_process;b.standard_size=bc.standard_size;b.pricing_method=bc.pricing_method;b.sales_unit_price=bc.default_sales_price;b.reference_purchase_price_snapshot=bc.reference_purchase_price;
 end if;
 b=jsonb_populate_record(b,p_data);b.quote_id=q.id;b.customer_id=q.customer_id;b.updated_at=now();
 if b.sales_unit_price is null then raise exception using errcode='22023',message='custom_sales_price_required';end if;
 insert into public.board_bom_items(id,customer_id,quote_id,item_no,space,part_use,board_id,board_name,brand,substrate,thickness_mm,color_name,color_code,finish_process,eco_grade,edge_process,standard_size,pricing_method,unit,quantity,sales_unit_price,reference_purchase_price_snapshot,edge_length_m,edge_charge_mode,edge_sales_price_per_meter_snapshot,utilization_rate,linear_width_mm,note,created_by,created_at,updated_at)
 values(b.id,b.customer_id,b.quote_id,b.item_no,b.space,b.part_use,b.board_id,b.board_name,b.brand,b.substrate,b.thickness_mm,b.color_name,b.color_code,b.finish_process,b.eco_grade,b.edge_process,b.standard_size,b.pricing_method,b.unit,b.quantity,b.sales_unit_price,b.reference_purchase_price_snapshot,b.edge_length_m,b.edge_charge_mode,b.edge_sales_price_per_meter_snapshot,b.utilization_rate,b.linear_width_mm,b.note,b.created_by,b.created_at,b.updated_at)
 on conflict(id) do update set item_no=excluded.item_no,space=excluded.space,part_use=excluded.part_use,board_id=excluded.board_id,board_name=excluded.board_name,brand=excluded.brand,substrate=excluded.substrate,thickness_mm=excluded.thickness_mm,color_name=excluded.color_name,color_code=excluded.color_code,finish_process=excluded.finish_process,eco_grade=excluded.eco_grade,edge_process=excluded.edge_process,standard_size=excluded.standard_size,pricing_method=excluded.pricing_method,unit=excluded.unit,quantity=excluded.quantity,sales_unit_price=excluded.sales_unit_price,reference_purchase_price_snapshot=excluded.reference_purchase_price_snapshot,edge_length_m=excluded.edge_length_m,edge_charge_mode=excluded.edge_charge_mode,edge_sales_price_per_meter_snapshot=excluded.edge_sales_price_per_meter_snapshot,utilization_rate=excluded.utilization_rate,linear_width_mm=excluded.linear_width_mm,note=excluded.note,updated_at=excluded.updated_at;
 out_id=b.id;
 elsif p_kind='hardware' then
 perform custom_private.validate_keys(p_data,array['item_no','use_location','hardware_id','hardware_name','major_category','spec','brand','model','soft_close','unit','quantity','sales_unit_price','included_in_base','note']);
 if p_id is not null then select * into h from public.hardware_bom_items where id=p_id and quote_id=p_quote_id and factory_order_id is null;
 if not found then raise exception using errcode='42501',message='custom_item_forbidden';end if;
 else h.id=gen_random_uuid();h.item_no=1;h.use_location='';h.hardware_name='';h.major_category='';h.spec='';h.brand='';h.model='';h.soft_close=false;h.unit='个';h.quantity=0;h.sales_unit_price=0;h.included_in_base=false;h.note='';h.created_at=now();h.created_by=auth.uid();end if;
 if p_data ? 'hardware_id' and nullif(p_data->>'hardware_id','') is not null then
 select * into hc from public.hardware_catalog where id=(p_data->>'hardware_id')::uuid and status<>'停用';
 if not found then raise exception using errcode='22023',message='custom_catalog_unavailable';end if;
 h.hardware_id=hc.id;h.hardware_name=hc.hardware_name;h.major_category=hc.major_category;h.spec=hc.spec;h.brand=hc.brand;h.model=hc.model;h.soft_close=hc.soft_close;h.unit=hc.unit;h.sales_unit_price=hc.default_sales_price;h.reference_purchase_price_snapshot=hc.reference_purchase_price;
 end if;
 h=jsonb_populate_record(h,p_data);h.quote_id=q.id;h.customer_id=q.customer_id;h.updated_at=now();
 if h.sales_unit_price is null then raise exception using errcode='22023',message='custom_sales_price_required';end if;
 insert into public.hardware_bom_items(id,customer_id,quote_id,item_no,use_location,hardware_id,hardware_name,major_category,spec,brand,model,soft_close,unit,quantity,sales_unit_price,reference_purchase_price_snapshot,included_in_base,note,created_by,created_at,updated_at)
 values(h.id,h.customer_id,h.quote_id,h.item_no,h.use_location,h.hardware_id,h.hardware_name,h.major_category,h.spec,h.brand,h.model,h.soft_close,h.unit,h.quantity,h.sales_unit_price,h.reference_purchase_price_snapshot,h.included_in_base,h.note,h.created_by,h.created_at,h.updated_at)
 on conflict(id) do update set item_no=excluded.item_no,use_location=excluded.use_location,hardware_id=excluded.hardware_id,hardware_name=excluded.hardware_name,major_category=excluded.major_category,spec=excluded.spec,brand=excluded.brand,model=excluded.model,soft_close=excluded.soft_close,unit=excluded.unit,quantity=excluded.quantity,sales_unit_price=excluded.sales_unit_price,reference_purchase_price_snapshot=excluded.reference_purchase_price_snapshot,included_in_base=excluded.included_in_base,note=excluded.note,updated_at=excluded.updated_at;
 out_id=h.id;
 else raise exception using errcode='22023',message='custom_invalid_item_kind';end if;
 update public.quotes set amount=coalesce((select sum(sales_amount+edge_sales_amount) from public.board_bom_items where quote_id=q.id and factory_order_id is null),0)+coalesce((select sum(sales_amount) from public.hardware_bom_items where quote_id=q.id and factory_order_id is null),0) where id=q.id;
 return jsonb_build_object('id',out_id,'status','saved');
end $$;

-- Only executor-visible safe receipts support idempotent writes without making
-- cost rows readable to the factory actor who submitted them.
create table if not exists custom_private.write_receipts(
 request_id uuid primary key,actor_id uuid not null references auth.users(id),entity_id uuid not null,operation text not null,
 created_at timestamptz not null default now());
alter table custom_private.write_receipts enable row level security;
alter table custom_private.write_receipts force row level security;
revoke all on custom_private.write_receipts from public,anon,authenticated;
grant select,insert on custom_private.write_receipts to anju_custom_executor;
drop policy if exists custom_receipt_self on custom_private.write_receipts;
create policy custom_receipt_self on custom_private.write_receipts for all to anju_custom_executor
 using(actor_id=(select auth.uid())) with check(actor_id=(select auth.uid()));

create or replace function custom_private.delete_bom(p_quote_id uuid,p_kind text,p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare q public.quotes%rowtype;begin
 perform custom_private.require_roles(array['owner','designer']);
 select * into q from public.quotes where id=p_quote_id and business_line='custom' for update;
 if not found then raise exception using errcode='42501',message='custom_quote_forbidden';end if;
 if q.status<>'draft' then raise exception using errcode='22023',message='custom_quote_locked';end if;
 if p_kind='board' then delete from public.board_bom_items where id=p_id and quote_id=q.id and factory_order_id is null;
 elsif p_kind='hardware' then delete from public.hardware_bom_items where id=p_id and quote_id=q.id and factory_order_id is null;
 else raise exception using errcode='22023',message='custom_invalid_item_kind';end if;
 if not found then raise exception using errcode='42501',message='custom_item_forbidden';end if;
 update public.quotes set amount=coalesce((select sum(sales_amount+edge_sales_amount) from public.board_bom_items where quote_id=q.id and factory_order_id is null),0)+coalesce((select sum(sales_amount) from public.hardware_bom_items where quote_id=q.id and factory_order_id is null),0) where id=q.id;
 return jsonb_build_object('id',p_id,'status','deleted');end $$;
create or replace function custom_private.order_from_quote(p_quote_id uuid,p_factory_manager_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare q public.quotes%rowtype;out_id uuid;begin
 perform custom_private.require_roles(array['owner']);
 select * into q from public.quotes where id=p_quote_id and business_line='custom' for update;
 if not found then raise exception using errcode='42501',message='custom_quote_forbidden';end if;
 select id into out_id from public.factory_orders where custom_quote_id=q.id;
 if found then return jsonb_build_object('id',out_id,'status','existing');end if;
 if q.status<>'draft' then raise exception using errcode='22023',message='custom_quote_locked';end if;
 if not custom_private.is_factory_manager(p_factory_manager_id) then
 raise exception using errcode='22023',message='custom_factory_assignment_invalid';end if;
 if not exists(select 1 from public.board_bom_items where quote_id=q.id) and not exists(select 1 from public.hardware_bom_items where quote_id=q.id) then
 raise exception using errcode='22023',message='custom_empty_quote';end if;
 out_id=gen_random_uuid();
 insert into public.factory_orders(id,customer_id,factory_manager_id,custom_quote_id,status,order_amount,order_no,business_source,order_date,current_process)
 values(out_id,q.customer_id,p_factory_manager_id,q.id,'待开工',q.amount,'CUSTOM-'||out_id::text,'门店定制',current_date,'未排产');
 insert into public.board_bom_items(customer_id,factory_order_id,quote_id,source_item_id,item_no,space,part_use,board_id,board_name,brand,substrate,thickness_mm,color_name,color_code,finish_process,eco_grade,edge_process,standard_size,pricing_method,unit,quantity,sales_unit_price,reference_purchase_price_snapshot,edge_length_m,edge_charge_mode,edge_sales_price_per_meter_snapshot,utilization_rate,linear_width_mm,note,created_by)
 select b.customer_id,out_id,b.quote_id,b.id,b.item_no,b.space,b.part_use,b.board_id,b.board_name,b.brand,b.substrate,b.thickness_mm,b.color_name,b.color_code,b.finish_process,b.eco_grade,b.edge_process,b.standard_size,b.pricing_method,b.unit,b.quantity,b.sales_unit_price,b.reference_purchase_price_snapshot,b.edge_length_m,b.edge_charge_mode,b.edge_sales_price_per_meter_snapshot,b.utilization_rate,b.linear_width_mm,b.note,auth.uid()
 from public.board_bom_items b where b.quote_id=q.id and b.factory_order_id is null;
 insert into public.hardware_bom_items(customer_id,factory_order_id,quote_id,source_item_id,item_no,use_location,hardware_id,hardware_name,major_category,spec,brand,model,soft_close,unit,quantity,sales_unit_price,reference_purchase_price_snapshot,included_in_base,note,created_by)
 select h.customer_id,out_id,h.quote_id,h.id,h.item_no,h.use_location,h.hardware_id,h.hardware_name,h.major_category,h.spec,h.brand,h.model,h.soft_close,h.unit,h.quantity,h.sales_unit_price,h.reference_purchase_price_snapshot,h.included_in_base,h.note,auth.uid()
 from public.hardware_bom_items h where h.quote_id=q.id and h.factory_order_id is null;
 update public.quotes set status='ordered' where id=q.id;
 return jsonb_build_object('id',out_id,'status','created');
end $$;
create or replace function custom_private.factory_record_cost(p_order_id uuid,p_category text,p_quantity numeric,p_unit text,p_unit_cost numeric,p_note text,p_request_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare out_id uuid=gen_random_uuid();req uuid=coalesce(p_request_id,gen_random_uuid());begin
 perform custom_private.require_roles(array['owner','factory_manager']);
 if not custom_private.order_allowed(p_order_id) then raise exception using errcode='42501',message='custom_order_forbidden';end if;
 if p_category not in ('板材','封边','五金','人工','安装','外协','其他') or p_quantity is null or p_quantity<=0 or p_unit_cost is null or p_unit_cost<0 then
 raise exception using errcode='22023',message='custom_invalid_cost_input';end if;
 if not pg_try_advisory_xact_lock(hashtextextended(req::text,0)) then raise exception using errcode='40001',message='custom_retry_request';end if;
 select entity_id into out_id from custom_private.write_receipts where request_id=req and operation='cost';
 if found then return jsonb_build_object('id',out_id,'status','existing');end if;
 out_id=gen_random_uuid();
 insert into public.custom_cost_entries(id,factory_order_id,category,quantity,unit,unit_cost,amount,note,created_by,request_id)
 values(out_id,p_order_id,p_category,p_quantity,p_unit,p_unit_cost,round(p_quantity*p_unit_cost,2),coalesce(p_note,''),auth.uid(),req);
 insert into custom_private.write_receipts(request_id,actor_id,entity_id,operation) values(req,auth.uid(),out_id,'cost');
 return jsonb_build_object('id',out_id,'status','recorded');
end $$;
create or replace function custom_private.set_edge_rate(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$ declare out_id uuid=gen_random_uuid();begin
 perform custom_private.require_roles(array['owner']);
 perform custom_private.validate_keys(p_data,array['edge_process','processing_mode','sales_price_per_meter','cost_per_meter','effective_from','effective_to']);
 perform pg_advisory_xact_lock(hashtextextended((p_data->>'edge_process')||':'||(p_data->>'processing_mode'),0));
 if exists(select 1 from public.edge_process_rates r where r.edge_process=p_data->>'edge_process' and r.processing_mode=p_data->>'processing_mode'
 and r.effective_from<=coalesce((p_data->>'effective_to')::date,'infinity'::date) and coalesce(r.effective_to,'infinity'::date)>=(p_data->>'effective_from')::date) then
 raise exception using errcode='22023',message='custom_edge_period_overlaps';end if;
 insert into public.edge_process_rates(id,edge_process,processing_mode,sales_price_per_meter,cost_per_meter,effective_from,effective_to,changed_by)
 values(out_id,p_data->>'edge_process',p_data->>'processing_mode',(p_data->>'sales_price_per_meter')::numeric,(p_data->>'cost_per_meter')::numeric,(p_data->>'effective_from')::date,(p_data->>'effective_to')::date,auth.uid());
 return jsonb_build_object('id',out_id,'status','saved');end $$;
create or replace function custom_private.record_edge_processing(p_order_id uuid,p_edge_process text,p_processing_mode text,p_length_m numeric,p_date date) returns jsonb
language plpgsql security definer set search_path='' as $$ declare r public.edge_process_rates%rowtype;out_id uuid=gen_random_uuid();begin
 perform custom_private.require_roles(array['owner','factory_manager']);
 if not custom_private.order_allowed(p_order_id) then raise exception using errcode='42501',message='custom_order_forbidden';end if;
 if p_length_m is null or p_length_m<=0 then raise exception using errcode='22023',message='custom_invalid_edge_length';end if;
 select * into r from public.edge_process_rates where edge_process=p_edge_process and processing_mode=p_processing_mode and effective_from<=p_date and (effective_to is null or effective_to>=p_date) order by effective_from desc limit 1;
 if not found then raise exception using errcode='22023',message='custom_edge_rate_missing';end if;
 insert into public.custom_cost_entries(id,factory_order_id,category,occurred_at,quantity,unit,unit_cost,amount,edge_rate_id,created_by)
 values(out_id,p_order_id,'封边',p_date,p_length_m,'米',r.cost_per_meter,round(p_length_m*r.cost_per_meter,2),r.id,auth.uid());
 return jsonb_build_object('id',out_id,'status','recorded');end $$;

drop policy if exists custom_executor_order_attachment_lookup on public.factory_orders;
create policy custom_executor_order_attachment_lookup on public.factory_orders for select to anju_custom_executor
 using(custom_quote_id is not null and app.role()='designer' and custom_private.customer_allowed(customer_id));
create or replace function custom_private.register_attachment(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare out_id uuid=gen_random_uuid();a public.custom_attachments%rowtype;begin
 perform custom_private.require_roles(array['owner','designer','factory_manager']);
 perform custom_private.validate_keys(p_data,array['customer_id','quote_id','factory_order_id','purchase_order_id','node_date','document_kind','file_name','mime_type','file_size']);
 a=jsonb_populate_record(a,p_data);
 if a.document_kind in ('quote','order') then
 if not custom_private.customer_allowed(a.customer_id) then raise exception using errcode='42501',message='custom_attachment_forbidden';end if;
 if a.document_kind='quote' and not exists(select 1 from public.quotes q where q.id=a.quote_id and q.customer_id=a.customer_id and q.business_line='custom') then raise exception using errcode='42501',message='custom_attachment_quote_forbidden';end if;
 if a.document_kind='order' and not exists(select 1 from public.factory_orders o where o.id=a.factory_order_id and o.customer_id=a.customer_id and o.custom_quote_id is not null) then raise exception using errcode='42501',message='custom_attachment_order_forbidden';end if;
 elsif a.document_kind='purchase' then
 perform custom_private.require_roles(array['owner']);
 if not custom_private.customer_allowed(a.customer_id) or not exists(select 1 from public.custom_purchase_orders where id=a.purchase_order_id) then raise exception using errcode='42501',message='custom_attachment_purchase_forbidden';end if;
 elsif a.document_kind='expense' then
 if not custom_private.order_allowed(a.factory_order_id) or not exists(select 1 from public.factory_orders o where o.id=a.factory_order_id and o.customer_id=a.customer_id) then raise exception using errcode='42501',message='custom_attachment_expense_forbidden';end if;
 else raise exception using errcode='22023',message='custom_attachment_kind_invalid';end if;
 if a.mime_type not in ('image/jpeg','image/png','image/webp','application/pdf','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') or a.file_size is null or a.file_size<=0 or a.file_size>20971520 or a.node_date is null then
 raise exception using errcode='22023',message='custom_file_invalid';end if;
 a.file_name=regexp_replace(coalesce(a.file_name,''),'[/\\[:cntrl:]]','_','g');
 if a.file_name='' then raise exception using errcode='22023',message='custom_file_name_required';end if;
 a.storage_path='custom/'||a.customer_id::text||'/'||to_char(a.node_date,'YYYY-MM-DD')||'/'||a.document_kind||'/'||out_id::text||'-'||a.file_name;
 insert into public.custom_attachments(id,customer_id,quote_id,factory_order_id,purchase_order_id,node_date,document_kind,storage_path,file_name,mime_type,file_size,uploaded_by)
 values(out_id,a.customer_id,a.quote_id,a.factory_order_id,a.purchase_order_id,a.node_date,a.document_kind,a.storage_path,a.file_name,a.mime_type,a.file_size,auth.uid());
 return jsonb_build_object('id',out_id,'storage_path',a.storage_path,'status','reserved');end $$;
create or replace function custom_private.storage_allowed(p_path text,p_write boolean) returns boolean
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null then return false;end if;
 return exists(select 1 from public.custom_attachments a where a.storage_path=p_path
 and ((app.role()='owner') or (app.role()='designer' and a.document_kind in ('quote','order') and custom_private.customer_allowed(a.customer_id))
 or (p_write and app.role()='factory_manager' and a.document_kind='expense' and a.uploaded_by=auth.uid() and custom_private.order_allowed(a.factory_order_id))));end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('custom-files','custom-files',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists custom_files_read on storage.objects;
create policy custom_files_read on storage.objects for select to authenticated using(bucket_id='custom-files' and custom_private.storage_allowed(name,false));
drop policy if exists custom_files_upload on storage.objects;
create policy custom_files_upload on storage.objects for insert to authenticated with check(bucket_id='custom-files' and custom_private.storage_allowed(name,true));
-- Files are immutable, use a new reserved path for replacements; no UPDATE/DELETE policy.

-- API wrappers have no elevation. All elevation is private, owned by a
-- Procurement lifecycle and stock writes are transactional and replay safe.
alter table public.custom_purchase_lines add column if not exists landed_amount numeric(14,2);
create or replace function custom_private.save_purchase(p_data jsonb,p_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare out_id uuid=coalesce(p_id,gen_random_uuid());p public.custom_purchase_orders%rowtype;j jsonb;a jsonb;l_id uuid;snapshot jsonb;
begin
 perform custom_private.require_roles(array['owner']);
 perform custom_private.validate_keys(p_data,array['supplier','bill_no','purchase_date','freight','discount','note','lines']);
 if p_id is not null then select * into p from public.custom_purchase_orders where id=p_id for update;
 if not found then raise exception using errcode='42501',message='custom_purchase_forbidden';end if;
 if p.status<>'待核对' then raise exception using errcode='22023',message='custom_purchase_locked';end if;
 else p.id=out_id;p.bill_no='';p.freight=0;p.discount=0;p.note='';p.status='待核对';p.created_by=auth.uid();p.created_at=now();end if;
 p=jsonb_populate_record(p,p_data-'lines');
 insert into public.custom_purchase_orders(id,supplier,bill_no,purchase_date,status,freight,discount,note,created_by,created_at)
 values(out_id,p.supplier,p.bill_no,p.purchase_date,p.status,p.freight,p.discount,p.note,p.created_by,p.created_at)
 on conflict(id) do update set supplier=excluded.supplier,bill_no=excluded.bill_no,purchase_date=excluded.purchase_date,freight=excluded.freight,discount=excluded.discount,note=excluded.note;
 if p_data ? 'lines' then
 if jsonb_typeof(p_data->'lines')<>'array' or jsonb_array_length(p_data->'lines')=0 then raise exception using errcode='22023',message='custom_purchase_lines_required';end if;
 delete from public.custom_purchase_allocations where purchase_line_id in(select id from public.custom_purchase_lines where purchase_order_id=out_id);
 delete from public.custom_purchase_lines where purchase_order_id=out_id;
 for j in select value from jsonb_array_elements(p_data->'lines') loop
 perform custom_private.validate_keys(j,array['board_id','hardware_id','temporary_item','item_name','brand','spec','unit','quantity','purchase_unit_price','declared_amount','note','allocations']);
 l_id=gen_random_uuid();snapshot='{}';
 if nullif(j->>'board_id','') is not null then
 select jsonb_build_object('material_name',b.material_name,'brand',b.brand,'substrate',b.substrate,'thickness_mm',b.thickness_mm,'color_name',b.color_name,'color_code',b.color_code,'finish_process',b.finish_process,'eco_grade',b.eco_grade,'edge_process',b.edge_process,'standard_size',b.standard_size) into snapshot from public.board_catalog b where id=(j->>'board_id')::uuid;
 elsif nullif(j->>'hardware_id','') is not null then
 select jsonb_build_object('hardware_name',h.hardware_name,'brand',h.brand,'model',h.model,'spec',h.spec,'unit',h.unit) into snapshot from public.hardware_catalog h where id=(j->>'hardware_id')::uuid;
 end if;
 if snapshot is null then raise exception using errcode='22023',message='custom_catalog_unavailable';end if;
 insert into public.custom_purchase_lines(id,purchase_order_id,board_id,hardware_id,temporary_item,item_name,brand,spec,catalog_snapshot,unit,quantity,purchase_unit_price,declared_amount,note)
 values(l_id,out_id,(j->>'board_id')::uuid,(j->>'hardware_id')::uuid,coalesce((j->>'temporary_item')::boolean,false),j->>'item_name',coalesce(j->>'brand',''),coalesce(j->>'spec',''),snapshot,j->>'unit',(j->>'quantity')::numeric,(j->>'purchase_unit_price')::numeric,(j->>'declared_amount')::numeric,coalesce(j->>'note',''));
 for a in select value from jsonb_array_elements(coalesce(j->'allocations','[]')) loop
 perform custom_private.validate_keys(a,array['factory_order_id','allocated_quantity','allocation_method']);
 if not custom_private.order_allowed((a->>'factory_order_id')::uuid) then raise exception using errcode='42501',message='custom_allocation_order_forbidden';end if;
 insert into public.custom_purchase_allocations(purchase_line_id,factory_order_id,allocated_quantity,allocation_method)
 values(l_id,(a->>'factory_order_id')::uuid,(a->>'allocated_quantity')::numeric,coalesce(a->>'allocation_method','手工'));
 end loop;
 if coalesce((select sum(allocated_quantity) from public.custom_purchase_allocations where purchase_line_id=l_id),0)>(j->>'quantity')::numeric then raise exception using errcode='23514',message='custom_overallocated_quantity';end if;
 end loop;
 end if;
 return jsonb_build_object('id',out_id,'status','待核对');end $$;
create or replace function custom_private.purchase_check(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.custom_purchase_orders%rowtype;l public.custom_purchase_lines%rowtype;a public.custom_purchase_allocations%rowtype;subtotal numeric;count_lines integer;carry numeric=0;net_line numeric;remaining_qty numeric;allocated_total numeric;
begin
 perform custom_private.require_roles(array['owner']);
 select * into p from public.custom_purchase_orders where id=p_id for update;
 if not found then raise exception using errcode='42501',message='custom_purchase_forbidden';end if;
 if p.status in ('已核对','已入库','已付款') then return jsonb_build_object('id',p.id,'status',p.status);end if;
 if exists(select 1 from public.custom_purchase_lines where purchase_order_id=p.id and line_amount<>declared_amount) then raise exception using errcode='23514',message='custom_purchase_amount_mismatch';end if;
 select sum(line_amount),count(*) into subtotal,count_lines from public.custom_purchase_lines where purchase_order_id=p.id;
 if count_lines=0 or subtotal+p.freight-p.discount<0 then raise exception using errcode='23514',message='custom_purchase_total_invalid';end if;
 for l in select * from public.custom_purchase_lines where purchase_order_id=p.id order by id loop
 count_lines=count_lines-1;
 if count_lines=0 then net_line=subtotal+p.freight-p.discount-carry;
 else net_line=l.line_amount+round((p.freight-p.discount)*case when subtotal=0 then 1.0/(select count(*) from public.custom_purchase_lines where purchase_order_id=p.id) else l.line_amount/subtotal end,2);end if;
 if net_line<0 then raise exception using errcode='23514',message='custom_negative_landed_cost';end if;
 carry=carry+net_line;
 update public.custom_purchase_lines set landed_amount=net_line where id=l.id;
 select coalesce(sum(allocated_quantity),0) into remaining_qty from public.custom_purchase_allocations where purchase_line_id=l.id;
 if remaining_qty>l.quantity then raise exception using errcode='23514',message='custom_overallocated_quantity';end if;
 allocated_total=0;
 for a in select * from public.custom_purchase_allocations where purchase_line_id=l.id order by id loop
 remaining_qty=remaining_qty-a.allocated_quantity;
 if remaining_qty=0 and coalesce((select sum(allocated_quantity) from public.custom_purchase_allocations where purchase_line_id=l.id),0)=l.quantity then
 update public.custom_purchase_allocations set allocated_amount=net_line-allocated_total where id=a.id;
 else update public.custom_purchase_allocations set allocated_amount=round(net_line*a.allocated_quantity/l.quantity,2) where id=a.id;end if;
 select allocated_total+allocated_amount into allocated_total from public.custom_purchase_allocations where id=a.id;
 end loop;
 end loop;
 update public.custom_purchase_orders set status='已核对',checked_at=now() where id=p.id;
 return jsonb_build_object('id',p.id,'status','已核对');end $$;
create or replace function custom_private.purchase_receive(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p public.custom_purchase_orders%rowtype;l public.custom_purchase_lines%rowtype;b public.custom_inventory_balances%rowtype;k text;catalog uuid;begin
 perform custom_private.require_roles(array['owner']);
 select * into p from public.custom_purchase_orders where id=p_id for update;
 if not found then raise exception using errcode='42501',message='custom_purchase_forbidden';end if;
 if p.status in ('已入库','已付款') then return jsonb_build_object('id',p.id,'status',p.status);end if;
 if p.status<>'已核对' then raise exception using errcode='22023',message='custom_check_before_receive';end if;
 for l in select * from public.custom_purchase_lines where purchase_order_id=p.id order by coalesce(board_id,hardware_id),unit,id loop
 if num_nonnulls(l.board_id,l.hardware_id)<>1 or l.landed_amount is null then raise exception using errcode='22023',message='custom_match_catalog_before_receive';end if;
 k=case when l.board_id is not null then 'board' else 'hardware' end;catalog=coalesce(l.board_id,l.hardware_id);
 insert into public.custom_inventory_balances(catalog_kind,catalog_id,unit) values(k,catalog,l.unit) on conflict do nothing;
 select * into b from public.custom_inventory_balances where catalog_kind=k and catalog_id=catalog and unit=l.unit for update;
 update public.custom_inventory_balances set quantity=b.quantity+l.quantity,average_unit_cost=(b.quantity*b.average_unit_cost+l.landed_amount)/(b.quantity+l.quantity),updated_at=now() where catalog_kind=k and catalog_id=catalog and unit=l.unit;
 insert into public.custom_inventory_transactions(catalog_kind,catalog_id,transaction_type,transaction_date,quantity,unit,purchase_line_id,unit_cost,total_cost,created_by)
 values(k,catalog,'入库',p.purchase_date,l.quantity,l.unit,l.id,l.landed_amount/l.quantity,l.landed_amount,auth.uid());
 end loop;
 update public.custom_purchase_orders set status='已入库',stocked_at=now() where id=p.id;
 return jsonb_build_object('id',p.id,'status','已入库');end $$;
create or replace function custom_private.purchase_pay(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare p public.custom_purchase_orders%rowtype;begin
 perform custom_private.require_roles(array['owner']);select * into p from public.custom_purchase_orders where id=p_id for update;
 if not found then raise exception using errcode='42501',message='custom_purchase_forbidden';end if;
 if p.status='已付款' then return jsonb_build_object('id',p.id,'status',p.status);end if;
 if p.status<>'已入库' then raise exception using errcode='22023',message='custom_receive_before_pay';end if;
 update public.custom_purchase_orders set status='已付款',paid_at=now() where id=p.id;
 return jsonb_build_object('id',p.id,'status','已付款');end $$;

-- Internal stock lookup grants factory writes access to valuation solely inside
-- executor functions. No valuation-reading function authorizes factory_manager.
drop policy if exists custom_stock_factory on public.custom_inventory_balances;
create policy custom_stock_factory on public.custom_inventory_balances for all to anju_custom_executor
 using(app.role()='factory_manager') with check(app.role()='factory_manager');
drop policy if exists custom_transaction_factory on public.custom_inventory_transactions;
create policy custom_transaction_factory on public.custom_inventory_transactions for all to anju_custom_executor
 using(app.role()='factory_manager' and custom_private.order_allowed(factory_order_id))
 with check(app.role()='factory_manager' and custom_private.order_allowed(factory_order_id) and created_by=(select auth.uid()));
create or replace function custom_private.material_issue(p_order_id uuid,p_kind text,p_catalog_id uuid,p_quantity numeric,p_unit text,p_date date,p_request_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b public.custom_inventory_balances%rowtype;out_id uuid=gen_random_uuid();req uuid=coalesce(p_request_id,gen_random_uuid());begin
 perform custom_private.require_roles(array['owner','factory_manager']);
 if not custom_private.order_allowed(p_order_id) then raise exception using errcode='42501',message='custom_order_forbidden';end if;
 if p_quantity is null or p_quantity<=0 then raise exception using errcode='23514',message='custom_invalid_quantity';end if;
 if not pg_try_advisory_xact_lock(hashtextextended(req::text,0)) then raise exception using errcode='40001',message='custom_retry_request';end if;
 select entity_id into out_id from custom_private.write_receipts where request_id=req and operation='issue';
 if found then return jsonb_build_object('id',out_id,'status','existing');end if;
 select * into b from public.custom_inventory_balances where catalog_kind=p_kind and catalog_id=p_catalog_id and unit=p_unit for update;
 if not found or b.quantity<p_quantity then raise exception using errcode='23514',message='custom_insufficient_stock';end if;
 out_id=gen_random_uuid();
 update public.custom_inventory_balances set quantity=quantity-p_quantity,updated_at=now() where catalog_kind=p_kind and catalog_id=p_catalog_id and unit=p_unit;
 insert into public.custom_inventory_transactions(id,catalog_kind,catalog_id,transaction_type,transaction_date,quantity,unit,factory_order_id,unit_cost,total_cost,created_by,request_id)
 values(out_id,p_kind,p_catalog_id,'领料',p_date,p_quantity,p_unit,p_order_id,b.average_unit_cost,round(p_quantity*b.average_unit_cost,2),auth.uid(),req);
 insert into public.custom_cost_entries(factory_order_id,category,occurred_at,quantity,unit,unit_cost,amount,source_transaction_id,created_by)
 values(p_order_id,case when p_kind='board' then '板材' else '五金' end,p_date,p_quantity,p_unit,b.average_unit_cost,round(p_quantity*b.average_unit_cost,2),out_id,auth.uid());
 insert into custom_private.write_receipts(request_id,actor_id,entity_id,operation) values(req,auth.uid(),out_id,'issue');
 return jsonb_build_object('id',out_id,'status','issued','quantity',p_quantity);end $$;
create or replace function custom_private.material_return(p_source_transaction_id uuid,p_quantity numeric,p_date date,p_request_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare tx public.custom_inventory_transactions%rowtype;b public.custom_inventory_balances%rowtype;out_id uuid=gen_random_uuid();req uuid=coalesce(p_request_id,gen_random_uuid());begin
 perform custom_private.require_roles(array['owner','factory_manager']);
 if p_quantity is null or p_quantity<=0 then raise exception using errcode='23514',message='custom_invalid_quantity';end if;
 if not pg_try_advisory_xact_lock(hashtextextended(req::text,0)) then raise exception using errcode='40001',message='custom_retry_request';end if;
 select entity_id into out_id from custom_private.write_receipts where request_id=req and operation='return';
 if found then return jsonb_build_object('id',out_id,'status','existing');end if;
 select * into tx from public.custom_inventory_transactions where id=p_source_transaction_id and transaction_type='领料' for update;
 if not found or not custom_private.order_allowed(tx.factory_order_id) then raise exception using errcode='42501',message='custom_source_forbidden';end if;
 if p_quantity+coalesce((select sum(quantity) from public.custom_inventory_transactions where source_transaction_id=tx.id and transaction_type='退料'),0)>tx.quantity then raise exception using errcode='23514',message='custom_excess_return';end if;
 select * into b from public.custom_inventory_balances where catalog_kind=tx.catalog_kind and catalog_id=tx.catalog_id and unit=tx.unit for update;
 out_id=gen_random_uuid();
 update public.custom_inventory_balances set quantity=b.quantity+p_quantity,average_unit_cost=(b.quantity*b.average_unit_cost+p_quantity*tx.unit_cost)/(b.quantity+p_quantity),updated_at=now() where catalog_kind=tx.catalog_kind and catalog_id=tx.catalog_id and unit=tx.unit;
 insert into public.custom_inventory_transactions(id,catalog_kind,catalog_id,transaction_type,transaction_date,quantity,unit,factory_order_id,source_transaction_id,unit_cost,total_cost,created_by,request_id)
 values(out_id,tx.catalog_kind,tx.catalog_id,'退料',p_date,p_quantity,tx.unit,tx.factory_order_id,tx.id,tx.unit_cost,round(p_quantity*tx.unit_cost,2),auth.uid(),req);
 insert into public.custom_cost_entries(factory_order_id,category,occurred_at,quantity,unit,unit_cost,amount,source_transaction_id,created_by)
 values(tx.factory_order_id,case when tx.catalog_kind='board' then '板材' else '五金' end,p_date,-p_quantity,tx.unit,tx.unit_cost,-round(p_quantity*tx.unit_cost,2),out_id,auth.uid());
 insert into custom_private.write_receipts(request_id,actor_id,entity_id,operation) values(req,auth.uid(),out_id,'return');
 return jsonb_build_object('id',out_id,'status','returned','quantity',p_quantity);end $$;

-- dedicated non-bypass role, and RLS checks use the original request JWT.
do $$ declare r record;begin
 for r in select * from (values
 ('custom_save_catalog','p_kind text,p_data jsonb,p_id uuid default null','save_catalog(p_kind,p_data,p_id)'),
 ('custom_create_quote','p_customer_id uuid,p_title text','create_quote(p_customer_id,p_title)'),
 ('custom_save_bom','p_quote_id uuid,p_kind text,p_data jsonb,p_id uuid default null','save_bom(p_quote_id,p_kind,p_data,p_id)'),
 ('custom_delete_bom','p_quote_id uuid,p_kind text,p_id uuid','delete_bom(p_quote_id,p_kind,p_id)'),
 ('custom_order_from_quote','p_quote_id uuid,p_factory_manager_id uuid','order_from_quote(p_quote_id,p_factory_manager_id)'),
 ('custom_factory_record_cost','p_order_id uuid,p_category text,p_quantity numeric,p_unit text,p_unit_cost numeric,p_note text,p_request_id uuid default null','factory_record_cost(p_order_id,p_category,p_quantity,p_unit,p_unit_cost,p_note,p_request_id)'),
 ('custom_set_edge_rate','p_data jsonb','set_edge_rate(p_data)'),
 ('custom_save_purchase','p_data jsonb,p_id uuid default null','save_purchase(p_data,p_id)'),
 ('custom_purchase_check','p_id uuid','purchase_check(p_id)'),
 ('custom_purchase_receive','p_id uuid','purchase_receive(p_id)'),
 ('custom_purchase_pay','p_id uuid','purchase_pay(p_id)'),
 ('custom_material_issue','p_order_id uuid,p_kind text,p_catalog_id uuid,p_quantity numeric,p_unit text,p_date date,p_request_id uuid default null','material_issue(p_order_id,p_kind,p_catalog_id,p_quantity,p_unit,p_date,p_request_id)'),
 ('custom_material_return','p_source_transaction_id uuid,p_quantity numeric,p_date date,p_request_id uuid default null','material_return(p_source_transaction_id,p_quantity,p_date,p_request_id)'),
 ('custom_record_edge_processing','p_order_id uuid,p_edge_process text,p_processing_mode text,p_length_m numeric,p_date date','record_edge_processing(p_order_id,p_edge_process,p_processing_mode,p_length_m,p_date)'),
 ('custom_register_attachment','p_data jsonb','register_attachment(p_data)')
 ) as wrappers(name,args,call) loop
 execute format('create or replace function api.%I(%s) returns jsonb language sql security invoker set search_path='''' as $fn$ select custom_private.%s $fn$',r.name,r.args,r.call);
 end loop;
 -- Revoke default PUBLIC EXECUTE on every new custom function, including helpers.
 for r in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='custom_private' and p.proname not in ('request_uid','request_role','is_factory_manager') loop
 execute format('alter function %s owner to anju_custom_executor',r.signature);
 execute format('revoke all on function %s from public,anon,authenticated',r.signature);
 execute format('grant execute on function %s to authenticated',r.signature);
 end loop;
 for r in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname like 'custom_%' loop
 execute format('revoke all on function %s from public,anon',r.signature);
 execute format('grant execute on function %s to authenticated',r.signature);
 end loop;
end $$;
revoke create on schema custom_private from anju_custom_executor;
notify pgrst,'reload schema';
commit;


