-- Step 1: secure cloud backend for the renovation (整装) workflow.
-- This migration adds reno-owned objects and appends only the new reno order
-- source to the existing renovation_gross month rollup. It does not change
-- existing custom objects, fixed-cost rows, or legacy renovation calculations.
begin;

-- Shared customer identity with renovation-only metadata. Existing custom
-- records and their existing columns/policies are left untouched.
alter table public.customers
  add column if not exists unit text not null default '',
  add column if not exists layout text not null default '',
  add column if not exists area_m2 numeric(10,2),
  add column if not exists source text not null default '',
  add column if not exists designer_id uuid references auth.users(id),
  add column if not exists foreman_id uuid references auth.users(id),
  add column if not exists stage text not null default '',
  add column if not exists next_followup_at date,
  add column if not exists last_followup_text text not null default '',
  add column if not exists business_status text not null default '线索',
  add column if not exists business_type text not null default '整装';
alter table public.customers drop constraint if exists customers_business_line_check;
alter table public.customers add constraint customers_business_line_check
  check (business_line in ('renovation','reno','reno+custom','custom','factory'));
create index if not exists customers_reno_designer_idx on public.customers(designer_id,business_line);
create index if not exists customers_reno_foreman_idx on public.customers(foreman_id,business_line);

create table if not exists public.reno_followups (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  designer_id uuid not null references auth.users(id),
  content text not null check(length(btrim(content))>0),
  followup_at timestamptz not null default now(),
  next_followup_at date,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  request_id uuid not null unique
);
create index if not exists reno_followups_customer_time_idx on public.reno_followups(customer_id,followup_at desc);

create table if not exists public.reno_quotes (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  quote_no text not null check(length(btrim(quote_no))>0),
  version integer not null default 1 check(version>0),
  status text not null default '草稿' check(status in ('草稿','已发客户','已签约')),
  designer_id uuid not null references auth.users(id),
  quote_date date not null default current_date,
  direct_amount numeric(14,2) not null default 0 check(direct_amount>=0),
  design_fee numeric(14,2) not null default 0 check(design_fee>=0),
  tax numeric(14,2) not null default 0 check(tax>=0),
  discount numeric(14,2) not null default 0 check(discount>=0),
  total_amount numeric(14,2) generated always as (direct_amount+design_fee+tax-discount) stored,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  signed_at timestamptz,
  unique(customer_id,quote_no,version),
  check(total_amount>=0)
);
create index if not exists reno_quotes_customer_date_idx on public.reno_quotes(customer_id,quote_date desc,version desc);

create table if not exists public.reno_quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.reno_quotes(id),
  line_no integer not null check(line_no>0),
  space text not null check(space in ('全屋/基础工程','客厅','餐厅','主卧','次卧','儿童房','厨房','主卫','次卫','阳台','水电','其他')),
  category text not null check(category in ('基装人工','主材','辅材','项目包干','其他')),
  item_name text not null check(length(btrim(item_name))>0),
  spec text not null default '',
  unit text not null check(unit in ('项','个','米','㎡','樘','套','批','次')),
  quantity numeric(14,3) not null check(quantity>=0),
  unit_price numeric(14,2) not null check(unit_price>=0),
  amount numeric(14,2) generated always as (quantity*unit_price) stored,
  in_package boolean not null default false,
  note text not null default '',
  unique(quote_id,line_no)
);
create index if not exists reno_quote_items_quote_idx on public.reno_quote_items(quote_id,line_no);

create table if not exists public.reno_orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  quote_id uuid not null unique references public.reno_quotes(id),
  contract_amount numeric(14,2) not null check(contract_amount>=0),
  business_status text not null default '已签约' check(business_status in ('已签约','施工中','已完工','已结算','搁置')),
  designer_id uuid not null references auth.users(id),
  foreman_id uuid references auth.users(id),
  signed_at timestamptz not null default now(),
  current_stage text not null default '开工交底',
  completed_at timestamptz,
  status text not null default '待开工' check(status in ('待开工','施工中','已完工','已结算')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  request_id uuid not null unique
);
create index if not exists reno_orders_customer_idx on public.reno_orders(customer_id,created_at desc);
create index if not exists reno_orders_foreman_idx on public.reno_orders(foreman_id,status);
create index if not exists reno_orders_completed_idx on public.reno_orders(completed_at) where completed_at is not null;

create table if not exists public.reno_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.reno_orders(id),
  source_item_id uuid not null references public.reno_quote_items(id),
  line_no integer not null,
  space text not null,
  category text not null,
  item_name text not null,
  spec text not null default '',
  unit text not null,
  quantity numeric(14,3) not null,
  unit_price numeric(14,2) not null,
  amount numeric(14,2) generated always as (quantity*unit_price) stored,
  in_package boolean not null default false,
  note text not null default '',
  unique(order_id,source_item_id),
  unique(order_id,line_no)
);

create table if not exists public.reno_cost_entries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.reno_orders(id),
  category text not null check(category in ('主材','辅材','水电人工','瓦工人工','木工人工','油工人工','安装人工','外协','运输清运','其他直接')),
  item_name text not null check(length(btrim(item_name))>0),
  supplier_or_crew text not null default '',
  quantity numeric(14,3) check(quantity is null or quantity>0),
  unit text not null check(unit in ('项','个','米','㎡','樘','套','批','次')),
  unit_price numeric(14,2) not null check(unit_price>=0),
  entry_kind text not null default 'cost' check(entry_kind in ('cost','reversal')),
  amount numeric(14,2) generated always as ((case when entry_kind='reversal' then -1 else 1 end)*coalesce(quantity,1)*unit_price) stored,
  occurred_at date not null default current_date,
  doc_status text not null default '待补' check(doc_status in ('有单据','待补','无')),
  attachment_path text,
  note text not null default '',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  request_id uuid unique,
  reverses_entry_id uuid references public.reno_cost_entries(id),
  check((entry_kind='reversal')=(reverses_entry_id is not null))
);
create unique index if not exists reno_cost_single_reversal_idx on public.reno_cost_entries(reverses_entry_id) where reverses_entry_id is not null;
create index if not exists reno_cost_order_date_idx on public.reno_cost_entries(order_id,occurred_at desc);

create table if not exists public.reno_payment_plans (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.reno_orders(id),
  stage_name text not null check(stage_name in ('定金/首付款','二期/水电款','三期/中期款','尾款/质保金')),
  ratio numeric(7,5) not null check(ratio>0 and ratio<=1),
  contract_amount_snapshot numeric(14,2) not null check(contract_amount_snapshot>=0),
  planned_amount numeric(14,2) generated always as (round(contract_amount_snapshot*ratio,2)) stored,
  planned_date date,
  sort_order integer not null default 0,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  request_id uuid not null unique,
  unique(order_id,stage_name)
);
create index if not exists reno_payment_plans_order_idx on public.reno_payment_plans(order_id,sort_order);

create table if not exists public.reno_payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.reno_orders(id),
  amount numeric(14,2) not null check(amount<>0),
  paid_at date not null default current_date,
  method text not null check(method in ('银行转账','微信','支付宝','现金','刷卡','其他','冲正')),
  voucher_path text,
  received_by uuid not null references auth.users(id),
  note text not null default '',
  created_at timestamptz not null default now(),
  request_id uuid unique,
  reverses_payment_id uuid references public.reno_payments(id),
  check((method='冲正')=(reverses_payment_id is not null))
);
create unique index if not exists reno_payment_single_reversal_idx on public.reno_payments(reverses_payment_id) where reverses_payment_id is not null;
create index if not exists reno_payments_order_date_idx on public.reno_payments(order_id,paid_at desc);

create table if not exists public.reno_stage_templates (
  seq integer primary key check(seq>0),
  name text not null unique,
  required_photo_hint text not null default '',
  is_active boolean not null default true
);
insert into public.reno_stage_templates(seq,name,required_photo_hint) values
 (1,'开工交底','现场原状、交底合影、墙体拆改标识'),
 (2,'拆除/墙体改造','拆后全景、新建墙体、垃圾清运'),
 (3,'水电改造','水电管线走向、强弱电箱、打压/通水测试'),
 (4,'防水工程','防水涂刷、闭水试验(48h)、楼下顶面'),
 (5,'瓦工(贴砖)','墙砖铺贴、地砖铺贴、空鼓检查、倒角'),
 (6,'木工(吊顶造型)','龙骨基层、吊顶完成、背景墙基层'),
 (7,'油工(墙面)','阴阳角/挂网、腻子打磨、面漆完成'),
 (8,'主材安装','木门、橱柜、卫浴、地板、灯具安装'),
 (9,'定制/橱柜安装','柜体安装、五金调试、收口'),
 (10,'竣工验收','全屋竣工、水电交付、质保卡/客户签收')
on conflict(seq) do nothing;

create table if not exists public.reno_order_stages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.reno_orders(id),
  seq integer not null,
  name text not null,
  planned_date date,
  actual_date date,
  status text not null default '未开始' check(status in ('未开始','进行中','已完成','已验收','异常')),
  accepted boolean not null default false,
  foreman_id uuid references auth.users(id),
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(order_id,seq),
  foreign key(seq) references public.reno_stage_templates(seq)
);
create index if not exists reno_order_stages_order_idx on public.reno_order_stages(order_id,seq);

create table if not exists public.reno_stage_events (
  id uuid primary key default gen_random_uuid(),
  stage_id uuid not null references public.reno_order_stages(id),
  previous_status text not null,
  new_status text not null,
  previous_actual_date date,
  new_actual_date date,
  previous_accepted boolean not null,
  new_accepted boolean not null,
  previous_note text not null,
  new_note text not null,
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  request_id uuid not null unique
);

create table if not exists public.reno_stage_photos (
  id uuid primary key default gen_random_uuid(),
  order_stage_id uuid not null references public.reno_order_stages(id),
  storage_path text not null unique,
  file_name text not null,
  file_size bigint not null check(file_size>0 and file_size<=20971520),
  uploaded_by uuid not null references auth.users(id),
  uploaded_at timestamptz not null default now(),
  request_id uuid not null unique
);
create index if not exists reno_stage_photos_stage_idx on public.reno_stage_photos(order_stage_id,uploaded_at desc);

create table if not exists public.reno_quote_attachments (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.reno_quotes(id),
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null,
  file_size bigint not null check(file_size>0 and file_size<=20971520),
  uploaded_by uuid not null references auth.users(id),
  uploaded_at timestamptz not null default now(),
  request_id uuid not null unique
);

create table if not exists public.reno_order_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.reno_orders(id),
  action text not null check(action in ('complete','reopen')),
  previous_status text not null,
  previous_completed_at timestamptz,
  new_status text not null,
  new_completed_at timestamptz,
  note text not null default '',
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  request_id uuid not null unique
);
create index if not exists reno_order_events_order_idx on public.reno_order_events(order_id,changed_at desc);

create table if not exists public.reno_mutation_receipts (
  request_id uuid primary key,
  actor_id uuid not null references auth.users(id),
  operation text not null,
  target_id uuid,
  response jsonb not null,
  created_at timestamptz not null default now()
);

-- Quote line amounts are generated in SQL. The quote subtotal is recalculated
-- from the rows, while signed quotes are immutable and require a new version.
create or replace function custom_private.reno_guard_quote_item()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_quote_id uuid; v_status text;
begin
  v_quote_id:=case when tg_op='DELETE' then old.quote_id else new.quote_id end;
  select q.status into v_status from public.reno_quotes q where q.id=v_quote_id for update;
  if v_status is null or v_status<>'草稿' then
    raise exception using errcode='42501',message='reno_quote_locked';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
create or replace function custom_private.reno_recalc_quote_total()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_quote_id uuid;
begin
  v_quote_id:=case when tg_op='DELETE' then old.quote_id else new.quote_id end;
  update public.reno_quotes q set direct_amount=coalesce((select sum(i.amount) from public.reno_quote_items i where i.quote_id=v_quote_id),0)
   where q.id=v_quote_id and q.status='草稿';
  return null;
end $$;
drop trigger if exists reno_quote_item_guard on public.reno_quote_items;
create trigger reno_quote_item_guard before insert or update or delete on public.reno_quote_items
for each row execute function custom_private.reno_guard_quote_item();
drop trigger if exists reno_quote_item_recalc on public.reno_quote_items;
create trigger reno_quote_item_recalc after insert or update or delete on public.reno_quote_items
for each row execute function custom_private.reno_recalc_quote_total();

create or replace function custom_private.reno_customer_allowed(p_customer_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.customers c
  where c.id=p_customer_id and c.business_line in ('reno','reno+custom')
   and (custom_private.request_role()='owner' or
        (custom_private.request_role()='designer' and coalesce(c.designer_id,c.owner_id)=custom_private.request_uid())))
$$;
alter function custom_private.reno_customer_allowed(uuid) owner to postgres;
create or replace function custom_private.reno_order_allowed(p_order_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reno_orders o join public.customers c on c.id=o.customer_id
  where o.id=p_order_id and c.business_line in ('reno','reno+custom')
   and (custom_private.request_role()='owner'
     or (custom_private.request_role()='designer' and o.designer_id=custom_private.request_uid())
     or (custom_private.request_role()='foreman' and o.foreman_id=custom_private.request_uid())))
$$;
alter function custom_private.reno_order_allowed(uuid) owner to postgres;
create or replace function custom_private.reno_quote_allowed(p_quote_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reno_quotes q where q.id=p_quote_id and custom_private.reno_customer_allowed(q.customer_id))
$$;
alter function custom_private.reno_quote_allowed(uuid) owner to postgres;

-- Internal idempotency helpers. The receipt table is inaccessible to API
-- callers directly; the executor can check actor + operation before replay.
create or replace function custom_private.reno_request_replay(p_request_id uuid,p_operation text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v public.reno_mutation_receipts%rowtype;
begin
 if p_request_id is null then raise exception using errcode='22023',message='reno_request_id_required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into v from public.reno_mutation_receipts r where r.request_id=p_request_id;
 if found then
   if v.actor_id<>custom_private.request_uid() or v.operation<>p_operation then
     raise exception using errcode='23505',message='reno_request_id_conflict';
   end if;
   return v.response;
 end if;
 return null;
end $$;
create or replace function custom_private.reno_store_receipt(p_request_id uuid,p_operation text,p_target_id uuid,p_response jsonb)
returns void language sql volatile security definer set search_path='' as $$
 insert into public.reno_mutation_receipts(request_id,actor_id,operation,target_id,response)
 values(p_request_id,custom_private.request_uid(),p_operation,p_target_id,p_response)
$$;

-- All new tables are reachable only through the controlled executor. FORCE RLS
-- keeps the non-BYPASSRLS executor subject to the per-role policies below.
do $$ declare t text; begin
 foreach t in array array['reno_followups','reno_quotes','reno_quote_items','reno_orders','reno_order_items',
  'reno_cost_entries','reno_payment_plans','reno_payments','reno_stage_templates','reno_order_stages',
  'reno_stage_events','reno_stage_photos','reno_quote_attachments','reno_order_events','reno_mutation_receipts'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('alter table public.%I force row level security',t);
   execute format('revoke all on public.%I from public,anon,authenticated',t);
   execute format('grant select,insert,update,delete on public.%I to anju_custom_executor',t);
 end loop;
end $$;
grant select,insert,update on public.customers to anju_custom_executor;

-- Row ownership checks use only the existing trusted JWT helpers.
do $$ declare p record; begin
 for p in select unnest(array[
  'reno_executor_customer_select','reno_executor_customer_insert','reno_executor_customer_update',
  'reno_followup_access','reno_quote_access','reno_quote_item_access','reno_order_access','reno_order_foreman_select',
  'reno_order_item_access','reno_order_item_insert','reno_cost_owner_access','reno_payment_plan_access','reno_payment_access',
  'reno_stage_template_access','reno_stage_access','reno_stage_insert','reno_stage_update_access','reno_stage_event_access',
  'reno_stage_photo_access','reno_quote_attachment_access','reno_order_event_owner_access','reno_mutation_receipt_executor_access'
 ]) as policy_name loop
  if p.policy_name in ('reno_executor_customer_select','reno_executor_customer_insert','reno_executor_customer_update') then
   execute format('drop policy if exists %I on public.customers',p.policy_name);
  else
   execute format('drop policy if exists %I on public.%I',p.policy_name,case p.policy_name
    when 'reno_followup_access' then 'reno_followups' when 'reno_quote_access' then 'reno_quotes'
    when 'reno_quote_item_access' then 'reno_quote_items' when 'reno_order_access' then 'reno_orders'
    when 'reno_order_foreman_select' then 'reno_orders' when 'reno_order_item_access' then 'reno_order_items'
    when 'reno_order_item_insert' then 'reno_order_items'
    when 'reno_cost_owner_access' then 'reno_cost_entries' when 'reno_payment_plan_access' then 'reno_payment_plans'
    when 'reno_payment_access' then 'reno_payments' when 'reno_stage_template_access' then 'reno_stage_templates'
    when 'reno_stage_access' then 'reno_order_stages' when 'reno_stage_insert' then 'reno_order_stages'
    when 'reno_stage_update_access' then 'reno_order_stages'
    when 'reno_stage_event_access' then 'reno_stage_events' when 'reno_stage_photo_access' then 'reno_stage_photos'
    when 'reno_quote_attachment_access' then 'reno_quote_attachments' when 'reno_order_event_owner_access' then 'reno_order_events'
    when 'reno_mutation_receipt_executor_access' then 'reno_mutation_receipts' end);
  end if;
 end loop;
end $$;
drop policy if exists reno_executor_customer_select on public.customers;
create policy reno_executor_customer_select on public.customers for select to anju_custom_executor
 using(business_line in ('reno','reno+custom') and
   (custom_private.request_role()='owner'
    or (custom_private.request_role()='designer' and coalesce(designer_id,owner_id)=custom_private.request_uid())
    or (custom_private.request_role()='foreman' and foreman_id=custom_private.request_uid())));
drop policy if exists reno_executor_customer_insert on public.customers;
create policy reno_executor_customer_insert on public.customers for insert to anju_custom_executor
 with check(business_line in ('reno','reno+custom') and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and designer_id=custom_private.request_uid() and owner_id=custom_private.request_uid())));
drop policy if exists reno_executor_customer_update on public.customers;
create policy reno_executor_customer_update on public.customers for update to anju_custom_executor
 using(business_line in ('reno','reno+custom') and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and coalesce(designer_id,owner_id)=custom_private.request_uid())))
 with check(business_line in ('reno','reno+custom') and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and designer_id=custom_private.request_uid() and owner_id=custom_private.request_uid())));

create policy reno_followup_access on public.reno_followups for all to anju_custom_executor
 using(custom_private.reno_customer_allowed(customer_id)) with check(custom_private.reno_customer_allowed(customer_id));
create policy reno_quote_access on public.reno_quotes for all to anju_custom_executor
 using(custom_private.reno_customer_allowed(customer_id)) with check(custom_private.reno_customer_allowed(customer_id));
create policy reno_quote_item_access on public.reno_quote_items for all to anju_custom_executor
 using(custom_private.reno_quote_allowed(quote_id)) with check(custom_private.reno_quote_allowed(quote_id));
create policy reno_order_access on public.reno_orders for all to anju_custom_executor
 using(custom_private.request_role()='owner' or
   (custom_private.request_role()='designer' and designer_id=custom_private.request_uid()))
 with check(custom_private.request_role()='owner' or
   (custom_private.request_role()='designer' and designer_id=custom_private.request_uid()));
create policy reno_order_foreman_select on public.reno_orders for select to anju_custom_executor
 using(custom_private.request_role()='foreman' and foreman_id=custom_private.request_uid());
create policy reno_order_item_access on public.reno_order_items for select to anju_custom_executor
 using(exists(select 1 from public.reno_orders o where o.id=order_id and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and o.designer_id=custom_private.request_uid()))));
create policy reno_order_item_insert on public.reno_order_items for insert to anju_custom_executor
 with check(exists(select 1 from public.reno_orders o where o.id=order_id and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and o.designer_id=custom_private.request_uid()))));
create policy reno_cost_owner_access on public.reno_cost_entries for all to anju_custom_executor
 using(custom_private.request_role()='owner' and custom_private.reno_order_allowed(order_id))
 with check(custom_private.request_role()='owner' and custom_private.reno_order_allowed(order_id));
create policy reno_payment_plan_access on public.reno_payment_plans for all to anju_custom_executor
 using(exists(select 1 from public.reno_orders o where o.id=order_id and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and o.designer_id=custom_private.request_uid()))))
 with check(exists(select 1 from public.reno_orders o where o.id=order_id and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and o.designer_id=custom_private.request_uid()))));
create policy reno_payment_access on public.reno_payments for all to anju_custom_executor
 using(exists(select 1 from public.reno_orders o where o.id=order_id and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and o.designer_id=custom_private.request_uid()))))
 with check(exists(select 1 from public.reno_orders o where o.id=order_id and
   (custom_private.request_role()='owner' or (custom_private.request_role()='designer' and o.designer_id=custom_private.request_uid()))));
create policy reno_stage_template_access on public.reno_stage_templates for select to anju_custom_executor
 using(custom_private.request_role() in ('owner','designer','foreman'));
create policy reno_stage_access on public.reno_order_stages for select to anju_custom_executor
 using(custom_private.reno_order_allowed(order_id));
create policy reno_stage_insert on public.reno_order_stages for insert to anju_custom_executor
 with check(custom_private.request_role() in ('owner','designer') and exists(select 1 from public.reno_orders o where o.id=order_id and
   (custom_private.request_role()='owner' or o.designer_id=custom_private.request_uid())));
create policy reno_stage_update_access on public.reno_order_stages for update to anju_custom_executor
 using(custom_private.request_role()='owner' or
  (custom_private.request_role()='foreman' and foreman_id=custom_private.request_uid() and custom_private.reno_order_allowed(order_id)))
 with check(custom_private.request_role()='owner' or
  (custom_private.request_role()='foreman' and foreman_id=custom_private.request_uid() and custom_private.reno_order_allowed(order_id)));
create policy reno_stage_event_access on public.reno_stage_events for all to anju_custom_executor
 using(custom_private.request_role()='owner' or exists(select 1 from public.reno_order_stages s where s.id=stage_id and custom_private.reno_order_allowed(s.order_id)))
 with check(custom_private.request_role() in ('owner','foreman') and exists(select 1 from public.reno_order_stages s where s.id=stage_id and custom_private.reno_order_allowed(s.order_id)));
create policy reno_stage_photo_access on public.reno_stage_photos for all to anju_custom_executor
 using(exists(select 1 from public.reno_order_stages s where s.id=order_stage_id and custom_private.reno_order_allowed(s.order_id)))
 with check(exists(select 1 from public.reno_order_stages s where s.id=order_stage_id and custom_private.reno_order_allowed(s.order_id)) and
  (custom_private.request_role()='owner' or (custom_private.request_role()='foreman' and uploaded_by=custom_private.request_uid())));
create policy reno_quote_attachment_access on public.reno_quote_attachments for all to anju_custom_executor
 using(custom_private.reno_quote_allowed(quote_id)) with check(custom_private.reno_quote_allowed(quote_id) and uploaded_by=custom_private.request_uid());
create policy reno_order_event_owner_access on public.reno_order_events for all to anju_custom_executor
 using(custom_private.request_role()='owner' and custom_private.reno_order_allowed(order_id))
 with check(custom_private.request_role()='owner' and custom_private.reno_order_allowed(order_id));
create policy reno_mutation_receipt_executor_access on public.reno_mutation_receipts for all to anju_custom_executor
 using(true) with check(actor_id=custom_private.request_uid());

-- Storage access is path-scoped and rechecks customer/order ownership in SQL.
create or replace function custom_private.reno_storage_allowed(p_name text,p_action text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare p text[]; v_customer uuid; v_order uuid; v_kind text; v_seq integer;
begin
 if custom_private.request_uid() is null or p_action not in ('read','write') or p_name is null or p_name like '%..%' then return false; end if;
 p:=string_to_array(p_name,'/');
 if array_length(p,1)<5 or p[1]<>'reno' or p[2] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
 v_customer:=p[2]::uuid;
 if p[3]='quote' then
   if array_length(p,1)<>5 or p[4] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
   return custom_private.request_role() in ('owner','designer') and custom_private.reno_customer_allowed(v_customer);
 end if;
 if p[3] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or array_length(p,1)<>6 or p[5] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
 v_order:=p[3]::uuid;
 if p[4] ~ '^stage-[0-9]+$' then
   v_kind:='stage'; v_seq:=substring(p[4] from 7)::integer;
   if not exists(select 1 from public.reno_orders o where o.id=v_order and o.customer_id=v_customer)
      or not exists(select 1 from public.reno_order_stages s where s.order_id=v_order and s.seq=v_seq) then return false; end if;
   if p_action='write' then
     return custom_private.request_role()='owner'
       or (custom_private.request_role()='foreman' and exists(select 1 from public.reno_orders o where o.id=v_order and o.foreman_id=custom_private.request_uid()));
   end if;
   return custom_private.request_role()='owner'
      or (custom_private.request_role()='designer' and custom_private.reno_customer_allowed(v_customer))
      or (custom_private.request_role()='foreman' and exists(select 1 from public.reno_orders o where o.id=v_order and o.foreman_id=custom_private.request_uid()));
 elsif p[4] in ('cost','payment') then
   v_kind:=p[4];
   if not exists(select 1 from public.reno_orders o where o.id=v_order and o.customer_id=v_customer) then return false; end if;
   if v_kind='cost' then return custom_private.request_role()='owner'; end if;
   return custom_private.request_role()='owner'
      or (custom_private.request_role()='designer' and custom_private.reno_customer_allowed(v_customer));
 end if;
 return false;
exception when invalid_text_representation or numeric_value_out_of_range then return false;
end $$;
alter function custom_private.reno_storage_allowed(text,text) owner to postgres;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('reno-files','reno-files',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists reno_files_read on storage.objects;
create policy reno_files_read on storage.objects for select to authenticated
 using(bucket_id='reno-files' and custom_private.reno_storage_allowed(name,'read'));
drop policy if exists reno_files_insert on storage.objects;
create policy reno_files_insert on storage.objects for insert to authenticated
 with check(bucket_id='reno-files' and custom_private.reno_storage_allowed(name,'write'));
revoke all on function custom_private.reno_storage_allowed(text,text) from public,anon;
grant execute on function custom_private.reno_storage_allowed(text,text) to authenticated,anju_custom_executor;

-- Public API reads are explicit projections. Financial projections call an
-- owner guard before reading, so unauthorized roles receive 42501/HTTP 403.
create or replace function custom_private.read_reno_customers()
returns table(id uuid,business_line text,name text,phone text,community text,unit text,layout text,area_m2 numeric,source text,
 designer_id uuid,foreman_id uuid,stage text,next_followup_at date,last_followup_text text,business_status text,business_type text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select c.id,c.business_line,c.name,c.phone,c.community,c.unit,c.layout,c.area_m2,c.source,c.designer_id,c.foreman_id,c.stage,c.next_followup_at,c.last_followup_text,c.business_status,c.business_type,c.created_at
  from public.customers c where c.business_line in ('reno','reno+custom') and
   (custom_private.request_role()='owner' or coalesce(c.designer_id,c.owner_id)=custom_private.request_uid()) order by c.created_at desc;
end $$;
create or replace function custom_private.read_reno_followups()
returns table(id uuid,customer_id uuid,designer_id uuid,content text,followup_at timestamptz,next_followup_at date,created_by uuid,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select f.id,f.customer_id,f.designer_id,f.content,f.followup_at,f.next_followup_at,f.created_by,f.created_at
 from public.reno_followups f where custom_private.reno_customer_allowed(f.customer_id) order by f.followup_at desc;
end $$;
create or replace function custom_private.read_reno_quotes()
returns table(id uuid,customer_id uuid,quote_no text,version integer,status text,designer_id uuid,quote_date date,direct_amount numeric,design_fee numeric,tax numeric,discount numeric,total_amount numeric,created_by uuid,created_at timestamptz,signed_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select q.id,q.customer_id,q.quote_no,q.version,q.status,q.designer_id,q.quote_date,q.direct_amount,q.design_fee,q.tax,q.discount,q.total_amount,q.created_by,q.created_at,q.signed_at
 from public.reno_quotes q where custom_private.reno_customer_allowed(q.customer_id) order by q.quote_date desc,q.version desc;
end $$;
create or replace function custom_private.read_reno_quote_items()
returns table(id uuid,quote_id uuid,line_no integer,space text,category text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,amount numeric,in_package boolean,note text)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select i.id,i.quote_id,i.line_no,i.space,i.category,i.item_name,i.spec,i.unit,i.quantity,i.unit_price,i.amount,i.in_package,i.note
 from public.reno_quote_items i where custom_private.reno_quote_allowed(i.quote_id) order by i.quote_id,i.line_no;
end $$;
create or replace function custom_private.read_reno_orders()
returns table(id uuid,customer_id uuid,quote_id uuid,contract_amount numeric,business_status text,designer_id uuid,foreman_id uuid,signed_at timestamptz,current_stage text,completed_at timestamptz,status text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select o.id,o.customer_id,o.quote_id,o.contract_amount,o.business_status,o.designer_id,o.foreman_id,o.signed_at,o.current_stage,o.completed_at,o.status,o.created_at
 from public.reno_orders o where custom_private.request_role()='owner' or o.designer_id=custom_private.request_uid() order by o.created_at desc;
end $$;
create or replace function custom_private.read_reno_order_items()
returns table(id uuid,order_id uuid,source_item_id uuid,line_no integer,space text,category text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,amount numeric,in_package boolean,note text)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select i.id,i.order_id,i.source_item_id,i.line_no,i.space,i.category,i.item_name,i.spec,i.unit,i.quantity,i.unit_price,i.amount,i.in_package,i.note
 from public.reno_order_items i where custom_private.reno_order_allowed(i.order_id) order by i.order_id,i.line_no;
end $$;
create or replace function custom_private.read_foreman_reno_projects()
returns table(order_id uuid,customer_id uuid,customer_name text,phone text,community text,unit text,layout text,area_m2 numeric,
 business_status text,status text,current_stage text,signed_at timestamptz,completed_at timestamptz,foreman_id uuid)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['foreman']);
 return query select o.id,c.id,c.name,c.phone,c.community,c.unit,c.layout,c.area_m2,c.business_status,o.status,o.current_stage,o.signed_at,o.completed_at,o.foreman_id
 from public.reno_orders o join public.customers c on c.id=o.customer_id
 where o.foreman_id=custom_private.request_uid() and c.business_line in ('reno','reno+custom') order by o.created_at desc;
end $$;
-- This projection is safe for authenticated callers because it checks the
-- foreman role internally and returns production-only columns.
grant execute on function custom_private.read_foreman_reno_projects() to authenticated;
create or replace function custom_private.read_reno_order_stages()
returns table(id uuid,order_id uuid,seq integer,name text,planned_date date,actual_date date,status text,accepted boolean,foreman_id uuid,note text,photo_count bigint,required_photo_hint text)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer','foreman']);
 return query select s.id,s.order_id,s.seq,s.name,s.planned_date,s.actual_date,s.status,s.accepted,s.foreman_id,s.note,
  (select count(*) from public.reno_stage_photos p where p.order_stage_id=s.id),t.required_photo_hint
 from public.reno_order_stages s join public.reno_stage_templates t on t.seq=s.seq
 where custom_private.reno_order_allowed(s.order_id) order by s.order_id,s.seq;
end $$;
create or replace function custom_private.read_reno_stage_photos()
returns table(id uuid,order_stage_id uuid,storage_path text,file_name text,file_size bigint,uploaded_by uuid,uploaded_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer','foreman']);
 return query select p.id,p.order_stage_id,p.storage_path,p.file_name,p.file_size,p.uploaded_by,p.uploaded_at
 from public.reno_stage_photos p join public.reno_order_stages s on s.id=p.order_stage_id
 where custom_private.reno_order_allowed(s.order_id) order by p.uploaded_at desc;
end $$;
create or replace function custom_private.read_reno_payments()
returns table(id uuid,order_id uuid,amount numeric,paid_at date,method text,voucher_path text,received_by uuid,note text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select p.id,p.order_id,p.amount,p.paid_at,p.method,p.voucher_path,p.received_by,p.note,p.created_at
 from public.reno_payments p join public.reno_orders o on o.id=p.order_id
 where custom_private.request_role()='owner' or o.designer_id=custom_private.request_uid() order by p.paid_at desc,p.created_at desc;
end $$;
create or replace function custom_private.read_reno_payment_plans()
returns table(id uuid,order_id uuid,stage_name text,ratio numeric,planned_amount numeric,planned_date date,sort_order integer,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select p.id,p.order_id,p.stage_name,p.ratio,p.planned_amount,p.planned_date,p.sort_order,p.created_at
 from public.reno_payment_plans p join public.reno_orders o on o.id=p.order_id
 where custom_private.request_role()='owner' or o.designer_id=custom_private.request_uid() order by o.id,p.sort_order;
end $$;
create or replace function custom_private.read_reno_receivables()
returns table(order_id uuid,customer_id uuid,customer_name text,contract_amount numeric,received_amount numeric,receivable_amount numeric,status text,current_stage text,completed_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','designer']);
 return query select o.id,o.customer_id,c.name,o.contract_amount,coalesce(sum(p.amount),0)::numeric,
  o.contract_amount-coalesce(sum(p.amount),0)::numeric,o.status,o.current_stage,o.completed_at
 from public.reno_orders o join public.customers c on c.id=o.customer_id
 left join public.reno_payments p on p.order_id=o.id
 where custom_private.request_role()='owner' or o.designer_id=custom_private.request_uid()
 group by o.id,c.name order by o.created_at desc;
end $$;
create or replace function custom_private.read_owner_reno_cost_entries()
returns table(id uuid,order_id uuid,category text,item_name text,supplier_or_crew text,quantity numeric,unit text,unit_price numeric,amount numeric,occurred_at date,doc_status text,attachment_path text,note text,created_by uuid,created_at timestamptz,reverses_entry_id uuid)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query select e.id,e.order_id,e.category,e.item_name,e.supplier_or_crew,e.quantity,e.unit,e.unit_price,e.amount,e.occurred_at,e.doc_status,e.attachment_path,e.note,e.created_by,e.created_at,e.reverses_entry_id
 from public.reno_cost_entries e order by e.occurred_at desc,e.created_at desc;
end $$;
create or replace function custom_private.read_owner_reno_order_finance()
returns table(order_id uuid,customer_id uuid,customer_name text,status text,current_stage text,signed_at timestamptz,completed_at timestamptz,
 contract_amount numeric,main_material_cost numeric,auxiliary_material_cost numeric,water_electric_labor_cost numeric,tile_labor_cost numeric,
 carpentry_labor_cost numeric,paint_labor_cost numeric,installation_labor_cost numeric,outsourcing_cost numeric,transport_cost numeric,other_direct_cost numeric,
 direct_cost_total numeric,gross_profit numeric,gross_margin numeric,received_amount numeric,receivable_amount numeric,work_in_progress_spend numeric,hand_balance numeric)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query with costs as (
  select e.order_id,
   coalesce(sum(e.amount) filter(where e.category='主材'),0)::numeric main_material_cost,
   coalesce(sum(e.amount) filter(where e.category='辅材'),0)::numeric auxiliary_material_cost,
   coalesce(sum(e.amount) filter(where e.category='水电人工'),0)::numeric water_electric_labor_cost,
   coalesce(sum(e.amount) filter(where e.category='瓦工人工'),0)::numeric tile_labor_cost,
   coalesce(sum(e.amount) filter(where e.category='木工人工'),0)::numeric carpentry_labor_cost,
   coalesce(sum(e.amount) filter(where e.category='油工人工'),0)::numeric paint_labor_cost,
   coalesce(sum(e.amount) filter(where e.category='安装人工'),0)::numeric installation_labor_cost,
   coalesce(sum(e.amount) filter(where e.category='外协'),0)::numeric outsourcing_cost,
   coalesce(sum(e.amount) filter(where e.category='运输清运'),0)::numeric transport_cost,
   coalesce(sum(e.amount) filter(where e.category='其他直接'),0)::numeric other_direct_cost,
   coalesce(sum(e.amount),0)::numeric direct_cost_total
  from public.reno_cost_entries e group by e.order_id
 ), receipts as (
  select p.order_id,coalesce(sum(p.amount),0)::numeric received_amount from public.reno_payments p group by p.order_id
 )
 select o.id,o.customer_id,c.name,o.status,o.current_stage,o.signed_at,o.completed_at,o.contract_amount,
  coalesce(k.main_material_cost,0),coalesce(k.auxiliary_material_cost,0),coalesce(k.water_electric_labor_cost,0),coalesce(k.tile_labor_cost,0),
  coalesce(k.carpentry_labor_cost,0),coalesce(k.paint_labor_cost,0),coalesce(k.installation_labor_cost,0),coalesce(k.outsourcing_cost,0),coalesce(k.transport_cost,0),coalesce(k.other_direct_cost,0),
  coalesce(k.direct_cost_total,0),o.contract_amount-coalesce(k.direct_cost_total,0),
  case when o.contract_amount=0 then null::numeric else (o.contract_amount-coalesce(k.direct_cost_total,0))/o.contract_amount end,
  coalesce(r.received_amount,0),o.contract_amount-coalesce(r.received_amount,0),
  case when o.completed_at is null then coalesce(k.direct_cost_total,0) else 0::numeric end,
  coalesce(r.received_amount,0)-coalesce(k.direct_cost_total,0)
 from public.reno_orders o join public.customers c on c.id=o.customer_id left join costs k on k.order_id=o.id left join receipts r on r.order_id=o.id
 order by o.created_at desc;
end $$;
create or replace function custom_private.read_owner_reno_order_events()
returns table(id uuid,order_id uuid,action text,previous_status text,previous_completed_at timestamptz,new_status text,new_completed_at timestamptz,note text,changed_by uuid,changed_at timestamptz,request_id uuid)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query select e.id,e.order_id,e.action,e.previous_status,e.previous_completed_at,e.new_status,e.new_completed_at,e.note,e.changed_by,e.changed_at,e.request_id from public.reno_order_events e order by e.changed_at desc;
end $$;

-- Monthly renovation gross keeps the existing legacy quote calculation intact
-- and UNION ALLs only completed reno orders. The yearly view already sums this
-- monthly function, so its signature and custom/factory behavior stay intact.
create or replace function custom_private.read_owner_monthly_net_profit_step7()
returns table(month date,renovation_gross numeric,custom_gross numeric,factory_gross numeric,gross_total numeric,
 fixed_cost numeric,net_profit numeric,cumulative_net_profit numeric,custom_completed_order_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query
 with reno_gross_sources as (
   select date_trunc('month',q.created_at)::date as month,
     coalesce(sum(q.amount-coalesce(dc.cost,0)),0)::numeric as renovation_gross
   from public.quotes q
   left join lateral (select sum(d.amount) cost from public.direct_costs d where d.customer_id=q.customer_id) dc on true
   where q.business_line='renovation'
   group by date_trunc('month',q.created_at)::date
   union all
   select date_trunc('month',o.completed_at)::date as month,
     coalesce(sum(o.contract_amount-coalesce(k.cost_total,0)),0)::numeric as renovation_gross
   from public.reno_orders o
   left join lateral (select sum(e.amount) cost_total from public.reno_cost_entries e where e.order_id=o.id) k on true
   where o.completed_at is not null and o.status in ('已完工','已结算')
   group by date_trunc('month',o.completed_at)::date
 ), renovation_months as (
   select s.month,coalesce(sum(s.renovation_gross),0)::numeric renovation_gross from reno_gross_sources s group by s.month
 ), legacy_factory_months as (
   select date_trunc('month',coalesce(o.order_date,o.created_at))::date as month,
     coalesce(sum(coalesce(o.order_amount,0)-coalesce(o.board_cost,0)-coalesce(o.edge_cost,0)-coalesce(o.hardware_cost,0)
       -coalesce(o.processing_labor_cost,0)-coalesce(o.outsourcing_cost,0)-coalesce(o.other_cost,0)),0)::numeric as factory_gross
   from public.factory_orders o where o.custom_quote_id is null
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
   select r.month from renovation_months r union select f.month from legacy_factory_months f union
   select c.month from custom_completed_months c union select fc.month from fixed_cost_months fc
 ), rows as (
   select m.month,coalesce(r.renovation_gross,0)::numeric renovation_gross,
     coalesce(c.custom_gross,0)::numeric custom_gross,coalesce(f.factory_gross,0)::numeric factory_gross,
     coalesce(r.renovation_gross,0)+coalesce(c.custom_gross,0)+coalesce(f.factory_gross,0) gross_total,
     coalesce(fc.fixed_cost,0)::numeric fixed_cost,coalesce(c.order_count,0)::bigint custom_completed_order_count
   from months m left join renovation_months r using(month) left join legacy_factory_months f using(month)
   left join custom_completed_months c using(month) left join fixed_cost_months fc using(month)
 )
 select x.month,x.renovation_gross,x.custom_gross,x.factory_gross,x.gross_total,x.fixed_cost,
   x.gross_total-x.fixed_cost,
   sum(x.gross_total-x.fixed_cost) over(order by x.month rows between unbounded preceding and current row),
   x.custom_completed_order_count
 from rows x order by x.month;
end $$;

-- Helper ownership and grants: private data readers/writers are callable only
-- by the controlled executor; API projections below are the only public path.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='custom_private'
    and ((p.proname like 'reno_%' and p.proname not in ('reno_customer_allowed','reno_order_allowed','reno_quote_allowed','reno_storage_allowed'))
      or p.proname like 'read_%reno%') loop
   execute format('alter function %s owner to anju_custom_executor',f.sig);
   execute format('revoke all on function %s from public,anon,authenticated',f.sig);
   execute format('grant execute on function %s to anju_custom_executor',f.sig);
 end loop;
end $$;
grant execute on function custom_private.read_foreman_reno_projects() to authenticated;
do $$ declare f record; begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='custom_private' and p.proname like 'read_%reno%' loop
   execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;
grant select on public.reno_quotes,public.reno_quote_items,public.reno_orders,public.reno_order_items,
 public.reno_payment_plans,public.reno_payments,public.reno_stage_templates,public.reno_order_stages,
 public.reno_stage_photos,public.reno_quote_attachments,public.reno_mutation_receipts to anju_custom_executor;
grant insert,update on public.customers to anju_custom_executor;

-- Customer and follow-up writes.
create or replace function api.reno_save_customer(p_customer_id uuid,p_data jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=custom_private.request_uid(); v_role text:=custom_private.request_role(); v_id uuid; v_line text; v_type text; v_designer uuid; v_foreman uuid; v_response jsonb; v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'customer_save'); if v_existing is not null then return v_existing; end if;
 if jsonb_typeof(p_data)<>'object' or length(btrim(coalesce(p_data->>'name','')))=0 then raise exception using errcode='22023',message='reno_customer_invalid';end if;
 v_type:=coalesce(p_data->>'business_type','整装');
 if v_type not in ('整装','整装+定制') then raise exception using errcode='22023',message='reno_business_type_invalid';end if;
 v_line:=case when v_type='整装' then 'reno' else 'reno+custom' end;
 if coalesce(p_data->>'source','') not in ('','到店','老客转介','抖音','小区驻点','电话咨询','装饰公司渠道','其他') then raise exception using errcode='22023',message='reno_source_invalid';end if;
 if coalesce(p_data->>'business_status','线索') not in ('线索','量房','报价中','已签约','施工中','已完工','已结算','搁置') then raise exception using errcode='22023',message='reno_business_status_invalid';end if;
 if nullif(p_data->>'area_m2','') is not null and (p_data->>'area_m2')::numeric<0 then raise exception using errcode='22023',message='reno_area_invalid';end if;
 if v_role='designer' then v_designer:=v_actor; v_foreman:=nullif(p_data->>'foreman_id','')::uuid;
 else v_designer:=nullif(p_data->>'designer_id','')::uuid; v_foreman:=nullif(p_data->>'foreman_id','')::uuid; end if;
 if p_customer_id is null then
   insert into public.customers(business_line,name,phone,community,owner_id,unit,layout,area_m2,source,designer_id,foreman_id,stage,next_followup_at,last_followup_text,business_status,business_type)
   values(v_line,btrim(p_data->>'name'),coalesce(p_data->>'phone',''),coalesce(p_data->>'community',''),coalesce(v_designer,v_actor),coalesce(p_data->>'unit',''),coalesce(p_data->>'layout',''),nullif(p_data->>'area_m2','')::numeric,coalesce(p_data->>'source',''),v_designer,v_foreman,coalesce(p_data->>'stage',''),nullif(p_data->>'next_followup_at','')::date,coalesce(p_data->>'last_followup_text',''),coalesce(p_data->>'business_status','线索'),v_type)
   returning id into v_id;
 else
   if not custom_private.reno_customer_allowed(p_customer_id) then raise exception using errcode='42501',message='reno_customer_forbidden';end if;
   update public.customers set business_line=v_line,name=btrim(p_data->>'name'),phone=coalesce(p_data->>'phone',''),community=coalesce(p_data->>'community',''),
    unit=coalesce(p_data->>'unit',''),layout=coalesce(p_data->>'layout',''),area_m2=nullif(p_data->>'area_m2','')::numeric,source=coalesce(p_data->>'source',''),
    designer_id=case when v_role='owner' then coalesce(v_designer,designer_id) else v_actor end,
    foreman_id=case when v_role='owner' then v_foreman else foreman_id end,
    stage=coalesce(p_data->>'stage',''),next_followup_at=nullif(p_data->>'next_followup_at','')::date,last_followup_text=coalesce(p_data->>'last_followup_text',''),business_status=coalesce(p_data->>'business_status','线索'),business_type=v_type
   where id=p_customer_id and business_line in ('reno','reno+custom') returning id into v_id;
   if v_id is null then raise exception using errcode='42501',message='reno_customer_forbidden';end if;
 end if;
 v_response:=jsonb_build_object('status',case when p_customer_id is null then 'created' else 'updated' end,'id',v_id);
 perform custom_private.reno_store_receipt(p_request_id,'customer_save',v_id,v_response); return v_response;
end $$;
create or replace function api.reno_record_followup(p_customer_id uuid,p_content text,p_followup_at timestamptz,p_next_followup_at date,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=custom_private.request_uid(); v_id uuid; v_response jsonb; v_existing jsonb; v_designer uuid;
begin
 perform custom_private.require_roles(array['owner','designer']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'followup_create'); if v_existing is not null then return v_existing; end if;
 if not custom_private.reno_customer_allowed(p_customer_id) or length(btrim(coalesce(p_content,'')))=0 then raise exception using errcode='42501',message='reno_customer_forbidden';end if;
 select coalesce(c.designer_id,c.owner_id) into v_designer from public.customers c where c.id=p_customer_id;
 insert into public.reno_followups(customer_id,designer_id,content,followup_at,next_followup_at,created_by,request_id)
 values(p_customer_id,v_designer,p_content,coalesce(p_followup_at,now()),p_next_followup_at,v_actor,p_request_id) returning id into v_id;
 update public.customers set last_followup_text=p_content,next_followup_at=p_next_followup_at where id=p_customer_id;
 v_response:=jsonb_build_object('status','created','id',v_id); perform custom_private.reno_store_receipt(p_request_id,'followup_create',v_id,v_response); return v_response;
end $$;

-- Quote creation and edits. Item amounts and quote totals are computed by SQL.
create or replace function api.reno_create_quote(p_customer_id uuid,p_quote_no text,p_version integer,p_quote_date date,p_design_fee numeric,p_tax numeric,p_discount numeric,p_items jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=custom_private.request_uid();v_designer uuid;v_quote uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'quote_create'); if v_existing is not null then return v_existing; end if;
 if not custom_private.reno_customer_allowed(p_customer_id) then raise exception using errcode='42501',message='reno_customer_forbidden';end if;
 if length(btrim(coalesce(p_quote_no,'')))=0 or coalesce(p_version,0)<1 or coalesce(p_design_fee,0)<0 or coalesce(p_tax,0)<0 or coalesce(p_discount,0)<0 or jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception using errcode='22023',message='reno_quote_invalid';end if;
 select coalesce(c.designer_id,c.owner_id) into v_designer from public.customers c where c.id=p_customer_id;
 insert into public.reno_quotes(customer_id,quote_no,version,designer_id,quote_date,design_fee,tax,discount,created_by)
 values(p_customer_id,p_quote_no,p_version,v_designer,coalesce(p_quote_date,current_date),coalesce(p_design_fee,0),coalesce(p_tax,0),coalesce(p_discount,0),v_actor) returning id into v_quote;
 insert into public.reno_quote_items(quote_id,line_no,space,category,item_name,spec,unit,quantity,unit_price,in_package,note)
 select v_quote,x.line_no,x.space,x.category,x.item_name,coalesce(x.spec,''),x.unit,x.quantity,x.unit_price,coalesce(x.in_package,false),coalesce(x.note,'')
 from jsonb_to_recordset(coalesce(p_items,'[]'::jsonb)) as x(line_no integer,space text,category text,item_name text,spec text,unit text,quantity numeric,unit_price numeric,in_package boolean,note text)
 order by x.line_no;
 if not exists(select 1 from public.reno_quote_items i where i.quote_id=v_quote) then raise exception using errcode='22023',message='reno_quote_items_required';end if;
 v_response:=jsonb_build_object('status','created','id',v_quote);perform custom_private.reno_store_receipt(p_request_id,'quote_create',v_quote,v_response);return v_response;
end $$;
create or replace function api.reno_save_quote_item(p_quote_id uuid,p_item_id uuid,p_data jsonb,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);
 v_existing:=custom_private.reno_request_replay(p_request_id,'quote_item_save');if v_existing is not null then return v_existing;end if;
 if not custom_private.reno_quote_allowed(p_quote_id) then raise exception using errcode='42501',message='reno_quote_forbidden';end if;
 if p_item_id is null then
  insert into public.reno_quote_items(quote_id,line_no,space,category,item_name,spec,unit,quantity,unit_price,in_package,note)
  values(p_quote_id,(p_data->>'line_no')::integer,p_data->>'space',p_data->>'category',p_data->>'item_name',coalesce(p_data->>'spec',''),p_data->>'unit',(p_data->>'quantity')::numeric,(p_data->>'unit_price')::numeric,coalesce((p_data->>'in_package')::boolean,false),coalesce(p_data->>'note','')) returning id into v_id;
 else
  update public.reno_quote_items set line_no=(p_data->>'line_no')::integer,space=p_data->>'space',category=p_data->>'category',item_name=p_data->>'item_name',spec=coalesce(p_data->>'spec',''),unit=p_data->>'unit',quantity=(p_data->>'quantity')::numeric,unit_price=(p_data->>'unit_price')::numeric,in_package=coalesce((p_data->>'in_package')::boolean,false),note=coalesce(p_data->>'note','')
  where id=p_item_id and quote_id=p_quote_id returning id into v_id;
  if v_id is null then raise exception using errcode='42501',message='reno_quote_item_forbidden';end if;
 end if;
 v_response:=jsonb_build_object('status',case when p_item_id is null then 'created' else 'updated' end,'id',v_id);perform custom_private.reno_store_receipt(p_request_id,'quote_item_save',v_id,v_response);return v_response;
end $$;
create or replace function api.reno_delete_quote_item(p_item_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_quote uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'quote_item_delete');if v_existing is not null then return v_existing;end if;
 select i.quote_id into v_quote from public.reno_quote_items i where i.id=p_item_id;
 if v_quote is null or not custom_private.reno_quote_allowed(v_quote) then raise exception using errcode='42501',message='reno_quote_item_forbidden';end if;
 delete from public.reno_quote_items where id=p_item_id;
 v_response:=jsonb_build_object('status','deleted');perform custom_private.reno_store_receipt(p_request_id,'quote_item_delete',p_item_id,v_response);return v_response;
end $$;
create or replace function api.reno_mark_quote_sent(p_quote_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_response jsonb;v_existing jsonb;v_id uuid;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'quote_send');if v_existing is not null then return v_existing;end if;
 update public.reno_quotes set status='已发客户' where id=p_quote_id and status='草稿' and custom_private.reno_customer_allowed(customer_id) returning id into v_id;
 if v_id is null then raise exception using errcode='42501',message='reno_quote_forbidden_or_locked';end if;
 v_response:=jsonb_build_object('status','sent');perform custom_private.reno_store_receipt(p_request_id,'quote_send',v_id,v_response);return v_response;
end $$;
create or replace function api.reno_sign_quote(p_quote_id uuid,p_foreman_id uuid,p_signed_at timestamptz,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_quote public.reno_quotes%rowtype;v_customer public.customers%rowtype;v_order uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'quote_sign');if v_existing is not null then return v_existing;end if;
 select * into v_quote from public.reno_quotes q where q.id=p_quote_id and custom_private.reno_customer_allowed(q.customer_id) for update;
 if not found or v_quote.status<>'已发客户' then raise exception using errcode='42501',message='reno_quote_forbidden_or_not_sent';end if;
 select * into v_customer from public.customers c where c.id=v_quote.customer_id;
 if p_foreman_id is not null and not exists(select 1 from auth.users u where u.id=p_foreman_id and u.raw_app_meta_data->>'role'='foreman') then raise exception using errcode='22023',message='reno_foreman_invalid';end if;
 insert into public.reno_orders(customer_id,quote_id,contract_amount,business_status,designer_id,foreman_id,signed_at,current_stage,status,created_by,request_id)
 values(v_quote.customer_id,v_quote.id,v_quote.total_amount,'已签约',v_quote.designer_id,coalesce(p_foreman_id,v_customer.foreman_id),coalesce(p_signed_at,now()),'开工交底','待开工',custom_private.request_uid(),p_request_id) returning id into v_order;
 insert into public.reno_order_items(order_id,source_item_id,line_no,space,category,item_name,spec,unit,quantity,unit_price,in_package,note)
 select v_order,i.id,i.line_no,i.space,i.category,i.item_name,i.spec,i.unit,i.quantity,i.unit_price,i.in_package,i.note from public.reno_quote_items i where i.quote_id=v_quote.id order by i.line_no;
 insert into public.reno_order_stages(order_id,seq,name,foreman_id)
 select v_order,t.seq,t.name,coalesce(p_foreman_id,v_customer.foreman_id) from public.reno_stage_templates t where t.is_active order by t.seq;
 update public.reno_quotes set status='已签约',signed_at=coalesce(p_signed_at,now()) where id=v_quote.id;
 update public.customers set business_status='已签约',stage='开工交底',foreman_id=coalesce(p_foreman_id,v_customer.foreman_id) where id=v_quote.customer_id;
 v_response:=jsonb_build_object('status','created','order_id',v_order);perform custom_private.reno_store_receipt(p_request_id,'quote_sign',v_order,v_response);return v_response;
end $$;

-- Append-only direct cost entries and corrections.
create or replace function api.reno_record_cost(p_order_id uuid,p_category text,p_item_name text,p_supplier_or_crew text,p_quantity numeric,p_unit text,p_unit_price numeric,p_occurred_at date,p_doc_status text,p_attachment_path text,p_note text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner']);v_existing:=custom_private.reno_request_replay(p_request_id,'cost_create');if v_existing is not null then return v_existing;end if;
 if not custom_private.reno_order_allowed(p_order_id) then raise exception using errcode='42501',message='reno_order_forbidden';end if;
 if p_category not in ('主材','辅材','水电人工','瓦工人工','木工人工','油工人工','安装人工','外协','运输清运','其他直接') or p_unit not in ('项','个','米','㎡','樘','套','批','次') or p_unit_price is null or p_unit_price<0 or (p_quantity is not null and p_quantity<=0) or coalesce(p_doc_status,'待补') not in ('有单据','待补','无') then raise exception using errcode='22023',message='reno_cost_invalid';end if;
 if p_attachment_path is not null and not custom_private.reno_storage_allowed(p_attachment_path,'write') then raise exception using errcode='42501',message='reno_cost_attachment_forbidden';end if;
 insert into public.reno_cost_entries(order_id,category,item_name,supplier_or_crew,quantity,unit,unit_price,occurred_at,doc_status,attachment_path,note,created_by,request_id)
 values(p_order_id,p_category,p_item_name,coalesce(p_supplier_or_crew,''),p_quantity,p_unit,p_unit_price,coalesce(p_occurred_at,current_date),coalesce(p_doc_status,'待补'),p_attachment_path,coalesce(p_note,''),custom_private.request_uid(),p_request_id) returning id into v_id;
 v_response:=jsonb_build_object('status','created','id',v_id);perform custom_private.reno_store_receipt(p_request_id,'cost_create',v_id,v_response);return v_response;
end $$;
create or replace function api.reno_correct_cost(p_entry_id uuid,p_category text,p_item_name text,p_supplier_or_crew text,p_quantity numeric,p_unit text,p_unit_price numeric,p_occurred_at date,p_doc_status text,p_attachment_path text,p_note text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old public.reno_cost_entries%rowtype;v_reversal uuid;v_replacement uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner']);v_existing:=custom_private.reno_request_replay(p_request_id,'cost_correct');if v_existing is not null then return v_existing;end if;
 select * into v_old from public.reno_cost_entries e where e.id=p_entry_id for update;
 if not found or v_old.entry_kind<>'cost' or exists(select 1 from public.reno_cost_entries e where e.reverses_entry_id=v_old.id) then raise exception using errcode='23514',message='reno_cost_already_corrected';end if;
 if p_category not in ('主材','辅材','水电人工','瓦工人工','木工人工','油工人工','安装人工','外协','运输清运','其他直接') or p_unit not in ('项','个','米','㎡','樘','套','批','次') or p_unit_price is null or p_unit_price<0 or (p_quantity is not null and p_quantity<=0) or coalesce(p_doc_status,'待补') not in ('有单据','待补','无') then raise exception using errcode='22023',message='reno_cost_invalid';end if;
 if p_attachment_path is not null and not custom_private.reno_storage_allowed(p_attachment_path,'write') then raise exception using errcode='42501',message='reno_cost_attachment_forbidden';end if;
 insert into public.reno_cost_entries(order_id,category,item_name,supplier_or_crew,quantity,unit,unit_price,entry_kind,occurred_at,doc_status,attachment_path,note,created_by,reverses_entry_id)
 values(v_old.order_id,v_old.category,v_old.item_name,v_old.supplier_or_crew,v_old.quantity,v_old.unit,v_old.unit_price,'reversal',current_date,v_old.doc_status,v_old.attachment_path,'红冲：'||coalesce(p_note,''),custom_private.request_uid(),v_old.id) returning id into v_reversal;
 insert into public.reno_cost_entries(order_id,category,item_name,supplier_or_crew,quantity,unit,unit_price,occurred_at,doc_status,attachment_path,note,created_by,request_id)
 values(v_old.order_id,p_category,p_item_name,coalesce(p_supplier_or_crew,''),p_quantity,p_unit,p_unit_price,coalesce(p_occurred_at,current_date),coalesce(p_doc_status,'待补'),p_attachment_path,coalesce(p_note,''),custom_private.request_uid(),p_request_id) returning id into v_replacement;
 v_response:=jsonb_build_object('status','corrected','reversal_id',v_reversal,'replacement_id',v_replacement);perform custom_private.reno_store_receipt(p_request_id,'cost_correct',v_replacement,v_response);return v_response;
end $$;

-- Payment plans are based on the immutable contract snapshot. Payment rows are
-- append-only; corrections add a negative reversal and a replacement row.
create or replace function api.reno_save_payment_plan(p_order_id uuid,p_stage_name text,p_ratio numeric,p_planned_date date,p_sort_order integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_order public.reno_orders%rowtype;v_id uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'payment_plan_create');if v_existing is not null then return v_existing;end if;
 if not custom_private.reno_order_allowed(p_order_id) then raise exception using errcode='42501',message='reno_order_forbidden';end if;
 if p_stage_name not in ('定金/首付款','二期/水电款','三期/中期款','尾款/质保金') or p_ratio is null or p_ratio<=0 or p_ratio>1 then raise exception using errcode='22023',message='reno_payment_plan_invalid';end if;
 select * into v_order from public.reno_orders o where o.id=p_order_id;
 if (select coalesce(sum(x.ratio),0) from public.reno_payment_plans x where x.order_id=p_order_id)+p_ratio>1.00000 then raise exception using errcode='22023',message='reno_payment_plan_ratio_over_100';end if;
 insert into public.reno_payment_plans(order_id,stage_name,ratio,contract_amount_snapshot,planned_date,sort_order,created_by,request_id)
 values(p_order_id,p_stage_name,p_ratio,v_order.contract_amount,p_planned_date,coalesce(p_sort_order,0),custom_private.request_uid(),p_request_id) returning id into v_id;
 v_response:=jsonb_build_object('status','created','id',v_id);perform custom_private.reno_store_receipt(p_request_id,'payment_plan_create',v_id,v_response);return v_response;
end $$;
create or replace function api.reno_record_payment(p_order_id uuid,p_amount numeric,p_paid_at date,p_method text,p_voucher_path text,p_note text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'payment_create');if v_existing is not null then return v_existing;end if;
 if not custom_private.reno_order_allowed(p_order_id) or p_amount is null or p_amount<=0 or p_method not in ('银行转账','微信','支付宝','现金','刷卡','其他') then raise exception using errcode='42501',message='reno_payment_forbidden_or_invalid';end if;
 if p_voucher_path is not null and not custom_private.reno_storage_allowed(p_voucher_path,'write') then raise exception using errcode='42501',message='reno_payment_voucher_forbidden';end if;
 insert into public.reno_payments(order_id,amount,paid_at,method,voucher_path,received_by,note,request_id)
 values(p_order_id,p_amount,coalesce(p_paid_at,current_date),p_method,p_voucher_path,custom_private.request_uid(),coalesce(p_note,''),p_request_id) returning id into v_id;
 v_response:=jsonb_build_object('status','received','id',v_id);perform custom_private.reno_store_receipt(p_request_id,'payment_create',v_id,v_response);return v_response;
end $$;
create or replace function api.reno_correct_payment(p_payment_id uuid,p_new_amount numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old public.reno_payments%rowtype;v_reversal uuid;v_replacement uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'payment_correct');if v_existing is not null then return v_existing;end if;
 select * into v_old from public.reno_payments p where p.id=p_payment_id for update;
 if not found or v_old.reverses_payment_id is not null or exists(select 1 from public.reno_payments p where p.reverses_payment_id=v_old.id) or not custom_private.reno_order_allowed(v_old.order_id) or p_new_amount is null or p_new_amount<=0 then raise exception using errcode='42501',message='reno_payment_forbidden_or_corrected';end if;
 insert into public.reno_payments(order_id,amount,paid_at,method,voucher_path,received_by,note,reverses_payment_id)
 values(v_old.order_id,-v_old.amount,current_date,'冲正',v_old.voucher_path,custom_private.request_uid(),'红冲：'||coalesce(p_note,''),v_old.id) returning id into v_reversal;
 insert into public.reno_payments(order_id,amount,paid_at,method,voucher_path,received_by,note,request_id)
 values(v_old.order_id,p_new_amount,current_date,v_old.method,v_old.voucher_path,custom_private.request_uid(),coalesce(p_note,''),p_request_id) returning id into v_replacement;
 v_response:=jsonb_build_object('status','corrected','reversal_id',v_reversal,'replacement_id',v_replacement);perform custom_private.reno_store_receipt(p_request_id,'payment_correct',v_replacement,v_response);return v_response;
end $$;

-- Site-stage progress is the foreman's only write surface. Final completion
-- requires the owner to confirm the accepted final stage; reopen is audited.
create or replace function api.reno_foreman_update_stage(p_stage_id uuid,p_status text,p_actual_date date,p_accepted boolean,p_note text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_stage public.reno_order_stages%rowtype;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','foreman']);v_existing:=custom_private.reno_request_replay(p_request_id,'stage_update');if v_existing is not null then return v_existing;end if;
 select * into v_stage from public.reno_order_stages s where s.id=p_stage_id for update;
 if not found or not custom_private.reno_order_allowed(v_stage.order_id) or (custom_private.request_role()='foreman' and v_stage.foreman_id<>custom_private.request_uid()) then raise exception using errcode='42501',message='reno_stage_forbidden';end if;
 if p_status not in ('未开始','进行中','已完成','已验收','异常') then raise exception using errcode='22023',message='reno_stage_status_invalid';end if;
 update public.reno_order_stages set status=p_status,actual_date=p_actual_date,accepted=coalesce(p_accepted,false),note=coalesce(p_note,''),updated_at=now() where id=p_stage_id;
 insert into public.reno_stage_events(stage_id,previous_status,new_status,previous_actual_date,new_actual_date,previous_accepted,new_accepted,previous_note,new_note,changed_by,request_id)
 values(v_stage.id,v_stage.status,p_status,v_stage.actual_date,p_actual_date,v_stage.accepted,coalesce(p_accepted,false),v_stage.note,coalesce(p_note,''),custom_private.request_uid(),p_request_id);
 update public.reno_orders set current_stage=v_stage.name,business_status=case when status='待开工' then '施工中' else business_status end,status=case when status='待开工' then '施工中' else status end where id=v_stage.order_id and p_status in ('进行中','已完成','已验收');
 v_response:=jsonb_build_object('status','updated');perform custom_private.reno_store_receipt(p_request_id,'stage_update',p_stage_id,v_response);return v_response;
end $$;
create or replace function api.reno_foreman_upload_photo(p_stage_id uuid,p_storage_path text,p_file_name text,p_file_size bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_stage public.reno_order_stages%rowtype;v_id uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','foreman']);v_existing:=custom_private.reno_request_replay(p_request_id,'stage_photo_upload');if v_existing is not null then return v_existing;end if;
 select s.* into v_stage from public.reno_order_stages s where s.id=p_stage_id;
 if v_stage.id is null or not custom_private.reno_order_allowed(v_stage.order_id) or (custom_private.request_role()='foreman' and v_stage.foreman_id<>custom_private.request_uid()) then raise exception using errcode='42501',message='reno_stage_forbidden';end if;
 if p_file_size is null or p_file_size<=0 or p_file_size>20971520 or not custom_private.reno_storage_allowed(p_storage_path,'write') then raise exception using errcode='42501',message='reno_photo_path_forbidden';end if;
 insert into public.reno_stage_photos(order_stage_id,storage_path,file_name,file_size,uploaded_by,request_id)
 values(p_stage_id,p_storage_path,p_file_name,p_file_size,custom_private.request_uid(),p_request_id) returning id into v_id;
 v_response:=jsonb_build_object('status','uploaded','id',v_id);perform custom_private.reno_store_receipt(p_request_id,'stage_photo_upload',v_id,v_response);return v_response;
end $$;
create or replace function api.reno_register_quote_attachment(p_quote_id uuid,p_storage_path text,p_file_name text,p_mime_type text,p_file_size bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_customer uuid;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner','designer']);v_existing:=custom_private.reno_request_replay(p_request_id,'quote_attachment');if v_existing is not null then return v_existing;end if;
 select customer_id into v_customer from public.reno_quotes q where q.id=p_quote_id and custom_private.reno_quote_allowed(q.id);
 if v_customer is null or p_file_size<=0 or p_file_size>20971520 or p_mime_type not in ('image/jpeg','image/png','image/webp','application/pdf') or not custom_private.reno_storage_allowed(p_storage_path,'write') then raise exception using errcode='42501',message='reno_quote_attachment_forbidden';end if;
 insert into public.reno_quote_attachments(quote_id,storage_path,file_name,mime_type,file_size,uploaded_by,request_id)
 values(p_quote_id,p_storage_path,p_file_name,p_mime_type,p_file_size,custom_private.request_uid(),p_request_id) returning id into v_id;
 v_response:=jsonb_build_object('status','uploaded','id',v_id);perform custom_private.reno_store_receipt(p_request_id,'quote_attachment',v_id,v_response);return v_response;
end $$;
create or replace function api.reno_owner_complete_order(p_order_id uuid,p_completed_at timestamptz,p_note text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_order public.reno_orders%rowtype;v_stage public.reno_order_stages%rowtype;v_time timestamptz:=coalesce(p_completed_at,now());v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner']);v_existing:=custom_private.reno_request_replay(p_request_id,'order_complete');if v_existing is not null then return v_existing;end if;
 select * into v_order from public.reno_orders o where o.id=p_order_id for update;
 if not found then raise exception using errcode='42501',message='reno_order_forbidden';end if;
 if v_order.completed_at is not null then v_response:=jsonb_build_object('status','existing');perform custom_private.reno_store_receipt(p_request_id,'order_complete',p_order_id,v_response);return v_response;end if;
 select * into v_stage from public.reno_order_stages s where s.order_id=p_order_id and s.seq=10;
 if not found or v_stage.status<>'已验收' or not v_stage.accepted then raise exception using errcode='23514',message='reno_final_acceptance_required';end if;
 update public.reno_orders set status='已完工',business_status='已完工',completed_at=v_time,current_stage='竣工验收' where id=p_order_id;
 update public.customers set business_status='已完工',stage='竣工验收' where id=v_order.customer_id;
 insert into public.reno_order_events(order_id,action,previous_status,previous_completed_at,new_status,new_completed_at,note,changed_by,request_id)
 values(p_order_id,'complete',v_order.status,v_order.completed_at,'已完工',v_time,coalesce(p_note,''),custom_private.request_uid(),p_request_id);
 v_response:=jsonb_build_object('status','completed');perform custom_private.reno_store_receipt(p_request_id,'order_complete',p_order_id,v_response);return v_response;
end $$;
create or replace function api.reno_owner_reopen_order(p_order_id uuid,p_note text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_order public.reno_orders%rowtype;v_response jsonb;v_existing jsonb;
begin
 perform custom_private.require_roles(array['owner']);v_existing:=custom_private.reno_request_replay(p_request_id,'order_reopen');if v_existing is not null then return v_existing;end if;
 select * into v_order from public.reno_orders o where o.id=p_order_id for update;
 if not found then raise exception using errcode='42501',message='reno_order_forbidden';end if;
 if v_order.completed_at is null then v_response:=jsonb_build_object('status','not_completed');perform custom_private.reno_store_receipt(p_request_id,'order_reopen',p_order_id,v_response);return v_response;end if;
 update public.reno_orders set status='施工中',business_status='施工中',completed_at=null where id=p_order_id;
 update public.customers set business_status='施工中' where id=v_order.customer_id;
 insert into public.reno_order_events(order_id,action,previous_status,previous_completed_at,new_status,new_completed_at,note,changed_by,request_id)
 values(p_order_id,'reopen',v_order.status,v_order.completed_at,'施工中',null,coalesce(p_note,''),custom_private.request_uid(),p_request_id);
 v_response:=jsonb_build_object('status','reopened');perform custom_private.reno_store_receipt(p_request_id,'order_reopen',p_order_id,v_response);return v_response;
end $$;

-- API views backed by explicit role-checked functions.
do $$ declare v record; begin
 for v in select * from (values
  ('reno_customers','custom_private.read_reno_customers()'),
  ('reno_followups','custom_private.read_reno_followups()'),
  ('reno_quotes','custom_private.read_reno_quotes()'),
  ('reno_quote_items','custom_private.read_reno_quote_items()'),
  ('reno_orders','custom_private.read_reno_orders()'),
  ('reno_order_items','custom_private.read_reno_order_items()'),
  ('foreman_reno_projects','custom_private.read_foreman_reno_projects()'),
  ('reno_order_stages','custom_private.read_reno_order_stages()'),
  ('reno_stage_photos','custom_private.read_reno_stage_photos()'),
  ('reno_payments','custom_private.read_reno_payments()'),
  ('reno_payment_plans','custom_private.read_reno_payment_plans()'),
  ('reno_receivables','custom_private.read_reno_receivables()'),
  ('owner_reno_cost_entries','custom_private.read_owner_reno_cost_entries()'),
  ('owner_reno_order_finance','custom_private.read_owner_reno_order_finance()'),
  ('owner_reno_order_events','custom_private.read_owner_reno_order_events()')
 ) x(view_name,function_call) loop
   execute format('create or replace view api.%I with (security_invoker=false) as select * from %s',v.view_name,v.function_call);
   execute format('alter view api.%I owner to anju_custom_executor',v.view_name);
   execute format('revoke all on api.%I from public,anon',v.view_name);
   execute format('grant select on api.%I to authenticated',v.view_name);
 end loop;
end $$;

-- Expose all write RPCs only to authenticated callers; each checks its own role.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='api' and p.proname like 'reno_%' loop
   execute format('alter function %s owner to anju_custom_executor',f.sig);
   execute format('revoke all on function %s from public,anon',f.sig);
   execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $$;

-- The existing yearly view derives from this monthly function. Preserve its
-- column names/order and every existing custom/factory/fixed-cost expression.
notify pgrst,'reload schema';
commit;
