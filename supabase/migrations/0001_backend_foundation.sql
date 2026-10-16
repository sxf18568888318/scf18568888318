-- 安居经营台后端地基
-- 角色由 Auth user.app_metadata.role 管理：owner / designer / foreman / factory_manager
create schema if not exists app;
create schema if not exists api;

create or replace function app.role() returns text
language sql stable
set search_path = pg_catalog
as $$ select coalesce((select auth.jwt()->'app_metadata'->>'role'),'') $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null check (role in ('owner','designer','foreman','factory_manager')),
  created_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_line text not null check (business_line in ('renovation','custom','factory')),
  name text not null,
  phone text not null default '',
  community text not null default '',
  owner_id uuid not null references auth.users(id),
  status text not null default 'lead',
  created_at timestamptz not null default now()
);

create table if not exists public.followups (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id) on delete cascade,
  author_id uuid not null references auth.users(id), note text not null, next_at date, created_at timestamptz not null default now()
);

create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id) on delete cascade,
  business_line text not null check (business_line in ('renovation','custom')), title text not null default '整装报价',
  amount numeric(14,2) not null default 0, status text not null default 'draft', created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.quote_items (
  id uuid primary key default gen_random_uuid(), quote_id uuid not null references public.quotes(id) on delete cascade,
  category text not null, item_name text not null, unit text not null check (unit in ('项','㎡','延米')),
  quantity numeric(14,3) not null default 0, unit_price numeric(14,2) not null default 0, note text not null default ''
);

create table if not exists public.payment_plans (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id) on delete cascade,
  name text not null, planned_amount numeric(14,2) not null default 0, planned_date date, sort_order int not null default 0
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id) on delete cascade,
  amount numeric(14,2) not null, paid_at date not null default current_date, method text not null default '其他', note text not null default '', created_by uuid not null references auth.users(id)
);

create table if not exists public.sites (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null unique references public.customers(id) on delete cascade,
  foreman_id uuid references auth.users(id), current_stage text not null default 'demolition', created_at timestamptz not null default now()
);

create table if not exists public.site_stages (
  id uuid primary key default gen_random_uuid(), site_id uuid not null references public.sites(id) on delete cascade,
  stage_key text not null, status text not null default 'not_started' check (status in ('not_started','in_progress','completed')),
  note text not null default '', accepted_by text not null default '', updated_by uuid references auth.users(id), updated_at timestamptz not null default now(),
  unique(site_id, stage_key)
);

create table if not exists public.site_photos (
  id uuid primary key default gen_random_uuid(), site_id uuid not null references public.sites(id) on delete cascade,
  stage_key text not null, storage_path text not null, captured_at timestamptz not null default now(), uploaded_by uuid not null references auth.users(id), note text not null default ''
);

create table if not exists public.site_expenses (
  id uuid primary key default gen_random_uuid(), site_id uuid not null references public.sites(id) on delete cascade,
  amount numeric(14,2) not null, spent_at date not null default current_date, note text not null default '', created_by uuid not null references auth.users(id)
);

create table if not exists public.direct_costs (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers(id) on delete cascade,
  category text not null check (category in ('主材','人工','其他直接费用','板材','封边','五金','外协','其他')),
  amount numeric(14,2) not null, occurred_at date not null default current_date, note text not null default '', created_by uuid not null references auth.users(id)
);

create table if not exists public.factory_orders (
  id uuid primary key default gen_random_uuid(), customer_id uuid references public.customers(id), factory_manager_id uuid references auth.users(id),
  status text not null default 'received', order_amount numeric(14,2) not null default 0, created_at timestamptz not null default now()
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references auth.users(id), work_date date not null,
  status text not null default '出勤', hours numeric(8,2) not null default 0, note text not null default ''
);

create table if not exists public.fixed_costs (
  id uuid primary key default gen_random_uuid(), cost_month date not null, category text not null, amount numeric(14,2) not null, note text not null default ''
);

alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.followups enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;
alter table public.payment_plans enable row level security;
alter table public.payments enable row level security;
alter table public.sites enable row level security;
alter table public.site_stages enable row level security;
alter table public.site_photos enable row level security;
alter table public.site_expenses enable row level security;
alter table public.direct_costs enable row level security;
alter table public.factory_orders enable row level security;
alter table public.attendance enable row level security;
alter table public.fixed_costs enable row level security;

create or replace view api.my_customers with (security_invoker=true) as
select id,business_line,name,phone,community,owner_id,status,created_at from public.customers
where app.role() in ('owner','designer') and (app.role()='owner' or owner_id=auth.uid());
create or replace view api.my_quotes with (security_invoker=true) as
select q.id,q.customer_id,q.business_line,q.title,q.amount,q.status,q.created_by,q.created_at
from public.quotes q join public.customers c on c.id=q.customer_id
where app.role()='owner' or c.owner_id=auth.uid();
create or replace view api.my_sites with (security_invoker=true) as
select s.id,s.customer_id,s.foreman_id,s.current_stage,s.created_at from public.sites s
where app.role()='owner' or (app.role()='foreman' and s.foreman_id=auth.uid()) or (app.role()='factory_manager');
create or replace view api.my_site_stages with (security_invoker=true) as
select st.id,st.site_id,st.stage_key,st.status,st.note,st.accepted_by,st.updated_by,st.updated_at
from public.site_stages st join public.sites s on s.id=st.site_id
where app.role()='owner' or (app.role()='foreman' and s.foreman_id=auth.uid()) or app.role()='factory_manager';

revoke all on public.direct_costs, public.factory_orders, public.attendance, public.fixed_costs from anon, authenticated;
revoke all on public.payments from anon, authenticated;
grant select, insert, update on public.customers, public.followups, public.quotes, public.quote_items, public.payment_plans, public.payments to authenticated;
grant select, insert, update on public.sites, public.site_stages, public.site_photos, public.site_expenses to authenticated;
grant select, insert, update on public.direct_costs, public.factory_orders, public.attendance to authenticated;
grant select on api.my_customers, api.my_quotes, api.my_sites, api.my_site_stages to authenticated;

create policy customers_owner_read on public.customers for select to authenticated using (app.role()='owner' or (app.role()='designer' and owner_id=auth.uid()));
create policy customers_designer_insert on public.customers for insert to authenticated with check (app.role()='owner' or (app.role()='designer' and owner_id=auth.uid()));
create policy customers_owner_update on public.customers for update to authenticated using (app.role()='owner' or (app.role()='designer' and owner_id=auth.uid())) with check (app.role()='owner' or (app.role()='designer' and owner_id=auth.uid()));
create policy followups_access on public.followups for all to authenticated using (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())) with check (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()));
create policy quotes_access on public.quotes for all to authenticated using (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())) with check (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()));
create policy quote_items_access on public.quote_items for all to authenticated using (app.role()='owner' or exists(select 1 from public.quotes q join public.customers c on c.id=q.customer_id where q.id=quote_id and c.owner_id=auth.uid())) with check (app.role()='owner' or exists(select 1 from public.quotes q join public.customers c on c.id=q.customer_id where q.id=quote_id and c.owner_id=auth.uid()));
create policy payments_access on public.payments for all to authenticated using (app.role() in ('owner','designer') and (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()))) with check (app.role() in ('owner','designer') and (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())));
create policy payment_plans_access on public.payment_plans for all to authenticated using (app.role() in ('owner','designer') and (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()))) with check (app.role() in ('owner','designer') and (app.role()='owner' or exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid())));
create policy site_foreman_access on public.sites for select to authenticated using (app.role()='owner' or (app.role()='foreman' and foreman_id=auth.uid()) or app.role()='factory_manager');
create policy stage_foreman_update on public.site_stages for all to authenticated using (app.role()='owner' or exists(select 1 from public.sites s where s.id=site_id and (s.foreman_id=auth.uid() or app.role()='factory_manager'))) with check (app.role()='owner' or exists(select 1 from public.sites s where s.id=site_id and (s.foreman_id=auth.uid() or app.role()='factory_manager')));
create policy photo_foreman_upload on public.site_photos for insert to authenticated with check (app.role() in ('owner','foreman','factory_manager') and (app.role()='owner' or exists(select 1 from public.sites s where s.id=site_id and (s.foreman_id=auth.uid() or app.role()='factory_manager'))));
create policy photo_foreman_read on public.site_photos for select to authenticated using (app.role()='owner' or exists(select 1 from public.sites s where s.id=site_id and (s.foreman_id=auth.uid() or app.role()='factory_manager')));
create policy expense_foreman_insert on public.site_expenses for insert to authenticated with check (app.role() in ('owner','foreman') and (app.role()='owner' or exists(select 1 from public.sites s where s.id=site_id and s.foreman_id=auth.uid())));
create policy expense_foreman_read on public.site_expenses for select to authenticated using (app.role()='owner' or exists(select 1 from public.sites s where s.id=site_id and s.foreman_id=auth.uid()));
create policy factory_cost_access on public.direct_costs for all to authenticated using (app.role() in ('owner','factory_manager')) with check (app.role() in ('owner','factory_manager'));
create policy factory_order_access on public.factory_orders for all to authenticated using (app.role() in ('owner','factory_manager')) with check (app.role() in ('owner','factory_manager'));
create policy attendance_factory_access on public.attendance for all to authenticated using (app.role() in ('owner','factory_manager')) with check (app.role() in ('owner','factory_manager'));
create policy fixed_costs_owner_access on public.fixed_costs for all to authenticated using (app.role()='owner') with check (app.role()='owner');
create policy profile_self_read on public.profiles for select to authenticated using (id=auth.uid() or app.role()='owner');

insert into storage.buckets(id,name,public) values ('project-files','project-files',false) on conflict (id) do nothing;
create policy project_files_read on storage.objects for select to authenticated using (
  bucket_id='project-files' and (
    app.role()='owner' or
    (app.role()='designer' and (storage.foldername(name))[1]='renovation' and exists(select 1 from public.customers c where c.id=((storage.foldername(name))[2])::uuid and c.owner_id=auth.uid())) or
    (app.role()='foreman' and (storage.foldername(name))[1]='renovation' and exists(select 1 from public.sites s where s.id=((storage.foldername(name))[2])::uuid and s.foreman_id=auth.uid())) or
    (app.role()='factory_manager' and (storage.foldername(name))[1]='factory')
  )
);
create policy project_files_insert on storage.objects for insert to authenticated with check (
  bucket_id='project-files' and (
    app.role()='owner' or
    (app.role()='designer' and (storage.foldername(name))[1]='renovation' and exists(select 1 from public.customers c where c.id=((storage.foldername(name))[2])::uuid and c.owner_id=auth.uid())) or
    (app.role()='foreman' and (storage.foldername(name))[1]='renovation' and exists(select 1 from public.sites s where s.id=((storage.foldername(name))[2])::uuid and s.foreman_id=auth.uid())) or
    (app.role()='factory_manager' and (storage.foldername(name))[1]='factory')
  )
);
