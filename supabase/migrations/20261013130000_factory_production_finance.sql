begin;

-- Isolated factory ledger. Existing renovation/custom tables and RPCs are untouched.
create schema if not exists factory_private;
grant usage on schema factory_private to anju_custom_executor;
grant create on schema factory_private to anju_custom_executor;
revoke all on schema factory_private from public, anon, authenticated;

create table if not exists factory_private.mutation_receipts (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null,
  rpc_name text not null,
  request_id uuid not null,
  payload_hash text not null,
  created_at timestamptz not null default now(),
  unique(actor_id,rpc_name,request_id)
);

create table if not exists factory_private.work_orders (
  id uuid primary key default gen_random_uuid(),
  order_no text not null unique check(length(btrim(order_no))>0),
  customer_project text not null check(length(btrim(customer_project))>0),
  business_source text not null check(business_source in ('门店定制','整装配套','外加工')),
  order_date date not null default current_date,
  delivery_date date,
  current_process text not null default '未排产' check(current_process in ('未排产','到货待开料','开料','封边','排钻','加工','试装','打包','安装','已完工')),
  status text not null default '待开工' check(status in ('待开工','进行中','暂停','已完工','已结算')),
  order_amount numeric(14,2) check(order_amount is null or order_amount>=0),
  note text not null default '',
  completed_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists factory_private.employees (
  id uuid primary key default gen_random_uuid(),
  employee_name text not null check(length(btrim(employee_name))>0),
  job text not null default '',
  pay_method text not null check(pay_method in ('月薪','日薪','计件')),
  pay_rate numeric(14,4) not null check(pay_rate>=0),
  employment_status text not null default '在职' check(employment_status in ('在职','离职')),
  note text not null default '',
  updated_by uuid not null,
  updated_at timestamptz not null default now()
);

create table if not exists factory_private.employee_rate_history (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references factory_private.employees(id),
  effective_from date not null,
  pay_method text not null check(pay_method in ('月薪','日薪','计件')),
  pay_rate numeric(14,4) not null check(pay_rate>=0),
  employment_status text not null check(employment_status in ('在职','离职')),
  note text not null default '',
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique(employee_id,effective_from)
);

create table if not exists factory_private.attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references factory_private.employees(id),
  work_date date not null,
  job text not null default '',
  attendance_status text not null check(attendance_status in ('出勤','请假','旷工','加班','休息')),
  hours numeric(8,2) not null default 0 check(hours>=0),
  work_content text not null default '',
  piece_quantity numeric(14,3) not null default 0 check(piece_quantity>=0),
  overtime_hours numeric(8,2) not null default 0 check(overtime_hours>=0),
  note text not null default '',
  recorded_by uuid not null,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  unique(employee_id,work_date),
  unique(recorded_by,request_id)
);

create table if not exists factory_private.attendance_allocations (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references factory_private.attendance(id),
  order_id uuid not null references factory_private.work_orders(id),
  allocated_hours numeric(8,2) not null default 0 check(allocated_hours>=0),
  piece_quantity numeric(14,3) not null default 0 check(piece_quantity>=0),
  unique(attendance_id,order_id)
);

create table if not exists factory_private.materials (
  id uuid primary key default gen_random_uuid(),
  material_code text not null unique check(length(btrim(material_code))>0),
  material_name text not null check(length(btrim(material_name))>0),
  category text not null check(category in ('五金','辅料','板材')),
  cost_category text not null check(cost_category in ('板材','封边','五金','其他')),
  spec text not null default '',
  unit text not null check(unit in ('个','套','卷','箱','盒','张','米')),
  quantity_on_hand numeric(14,3) not null default 0 check(quantity_on_hand>=0),
  moving_average_cost numeric(14,4) not null default 0 check(moving_average_cost>=0),
  safety_stock numeric(14,3) not null default 0 check(safety_stock>=0),
  updated_at timestamptz not null default now()
);

create table if not exists factory_private.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  movement_date date not null default current_date,
  movement_type text not null check(movement_type in ('入库','出库','退料','盘盈','盘亏')),
  material_id uuid not null references factory_private.materials(id),
  quantity numeric(14,3) not null check(quantity>0),
  unit_price numeric(14,4) not null default 0 check(unit_price>=0),
  amount numeric(14,2) not null default 0 check(amount>=0),
  unit_cost_snapshot numeric(14,4) not null default 0 check(unit_cost_snapshot>=0),
  supplier_source text not null default '',
  order_id uuid references factory_private.work_orders(id),
  purpose text not null default '',
  handled_by text not null default '',
  note text not null default '',
  reverses_movement_id uuid references factory_private.inventory_movements(id),
  recorded_by uuid not null,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  unique(recorded_by,request_id),
  check((movement_type='退料')=(reverses_movement_id is not null))
);
drop index if exists factory_private.factory_inventory_one_return_per_issue;

create table if not exists factory_private.order_cost_entries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references factory_private.work_orders(id),
  cost_category text not null check(cost_category in ('板材','封边','五金','加工人工','外协','其他')),
  amount numeric(14,2) not null check(amount<>0),
  source_type text not null check(source_type in ('inventory','attendance','owner_entry','reversal')),
  source_id uuid,
  reverses_entry_id uuid references factory_private.order_cost_entries(id),
  note text not null default '',
  created_by uuid not null,
  created_at timestamptz not null default now(),
  request_id uuid not null,
  unique(created_by,request_id),
  unique(source_type,source_id),
  check((source_type='reversal')=(reverses_entry_id is not null))
);
drop index if exists factory_private.factory_order_cost_one_reversal;

create table if not exists factory_private.monthly_payroll_snapshots (
  id uuid primary key default gen_random_uuid(),
  payroll_month date not null,
  employee_id uuid not null references factory_private.employees(id),
  employee_name_snapshot text not null,
  pay_rate_snapshot numeric(14,4) not null,
  amount numeric(14,2) not null check(amount>=0),
  created_by uuid not null,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  unique(payroll_month,employee_id),
  unique(created_by,request_id)
);

create table if not exists factory_private.monthly_payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references factory_private.monthly_payroll_snapshots(id),
  amount numeric(14,2) not null check(amount<>0),
  note text not null,
  created_by uuid not null,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  unique(created_by,request_id)
);

create table if not exists factory_private.work_order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references factory_private.work_orders(id),
  old_status text,
  new_status text not null,
  old_process text,
  new_process text not null,
  changed_by uuid not null,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  unique(changed_by,request_id)
);

do $$
declare t text;
begin
  foreach t in array array['mutation_receipts','work_orders','employees','employee_rate_history','attendance','attendance_allocations','materials','inventory_movements','order_cost_entries','monthly_payroll_snapshots','monthly_payroll_adjustments','work_order_status_history'] loop
    execute format('alter table factory_private.%I enable row level security',t);
    execute format('alter table factory_private.%I force row level security',t);
    execute format('drop policy if exists factory_executor_access on factory_private.%I',t);
    execute format('create policy factory_executor_access on factory_private.%I for all to anju_custom_executor using (true) with check (true)',t);
  end loop;
end $$;

grant select,insert,update on all tables in schema factory_private to anju_custom_executor;
revoke all on all tables in schema factory_private from public,anon,authenticated;

create or replace function factory_private.claim_request(p_rpc text,p_request_id uuid,p_payload jsonb)
returns boolean language plpgsql volatile security invoker set search_path=''
as $$
declare v_actor uuid; v_hash text; v_existing text;
begin
  v_actor:=custom_private.request_uid();
  if v_actor is null or p_request_id is null then raise exception using errcode='42501',message='factory_forbidden'; end if;
  v_hash:=md5(coalesce(p_payload,'null'::jsonb)::text);
  insert into factory_private.mutation_receipts(actor_id,rpc_name,request_id,payload_hash)
  values(v_actor,p_rpc,p_request_id,v_hash) on conflict(actor_id,rpc_name,request_id) do nothing;
  if found then return false; end if;
  select payload_hash into v_existing from factory_private.mutation_receipts
   where actor_id=v_actor and rpc_name=p_rpc and request_id=p_request_id;
  if v_existing is distinct from v_hash then raise exception using errcode='22023',message='factory_request_id_reused'; end if;
  return true;
end $$;
alter function factory_private.claim_request(text,uuid,jsonb) owner to anju_custom_executor;
revoke all on function factory_private.claim_request(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function factory_private.claim_request(text,uuid,jsonb) to anju_custom_executor;

create or replace function api.owner_factory_work_orders()
returns table(id uuid,order_no text,customer_project text,business_source text,order_date date,delivery_date date,current_process text,status text,order_amount numeric,board_cost numeric,edge_cost numeric,hardware_cost numeric,processing_labor_cost numeric,outsourcing_cost numeric,other_cost numeric,total_cost numeric,gross_profit numeric,gross_margin numeric,completed_at timestamptz,note text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query
  select w.id,w.order_no,w.customer_project,w.business_source,w.order_date,w.delivery_date,w.current_process,w.status,w.order_amount,
    coalesce(sum(c.amount) filter(where c.cost_category='板材'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='封边'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='五金'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='加工人工'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='外协'),0)::numeric,
    coalesce(sum(c.amount) filter(where c.cost_category='其他'),0)::numeric,
    coalesce(sum(c.amount),0)::numeric,
    case when w.order_amount is null then null else w.order_amount-coalesce(sum(c.amount),0) end,
    case when coalesce(w.order_amount,0)=0 then null else (w.order_amount-coalesce(sum(c.amount),0))/w.order_amount end,
    w.completed_at,w.note
  from factory_private.work_orders w left join factory_private.order_cost_entries c on c.order_id=w.id
  group by w.id order by w.order_date desc,w.created_at desc;
end $$;

create or replace function api.owner_factory_order_cost_entries(p_order_id uuid)
returns table(id uuid,order_id uuid,cost_category text,amount numeric,source_type text,source_id uuid,reverses_entry_id uuid,note text,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select c.id,c.order_id,c.cost_category,c.amount,c.source_type,c.source_id,c.reverses_entry_id,c.note,c.created_at
   from factory_private.order_cost_entries c where c.order_id=p_order_id order by c.created_at,c.id;
end $$;

create or replace function api.factory_work_orders_safe()
returns table(id uuid,order_no text,customer_project text,business_source text,order_date date,delivery_date date,current_process text,status text,completed_at timestamptz,note text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select w.id,w.order_no,w.customer_project,w.business_source,w.order_date,w.delivery_date,w.current_process,w.status,w.completed_at,w.note
    from factory_private.work_orders w order by w.order_date desc,w.created_at desc;
end $$;

create or replace function api.owner_factory_employees()
returns table(id uuid,employee_name text,job text,pay_method text,pay_rate numeric,employment_status text,note text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select e.id,e.employee_name,e.job,e.pay_method,e.pay_rate,e.employment_status,e.note from factory_private.employees e order by e.employee_name;
end $$;

create or replace function api.factory_employees_safe()
returns table(id uuid,employee_name text,job text,employment_status text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select e.id,e.employee_name,e.job,e.employment_status from factory_private.employees e order by e.employee_name;
end $$;

create or replace function api.factory_attendance_safe(p_from date default null,p_to date default null)
returns table(id uuid,work_date date,employee_name text,job text,attendance_status text,hours numeric,work_content text,piece_quantity numeric,overtime_hours numeric,note text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select a.id,a.work_date,e.employee_name,a.job,a.attendance_status,a.hours,a.work_content,a.piece_quantity,a.overtime_hours,a.note
  from factory_private.attendance a join factory_private.employees e on e.id=a.employee_id
  where (p_from is null or a.work_date>=p_from) and (p_to is null or a.work_date<=p_to)
  order by a.work_date desc,a.created_at desc;
end $$;

create or replace function api.owner_factory_payroll(p_month date default null)
returns table(payroll_month date,employee_name text,pay_method text,amount numeric,source text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query
  select s.payroll_month,s.employee_name_snapshot,'月薪'::text,s.amount+coalesce(a.adjustments,0),'固定人工'::text
  from factory_private.monthly_payroll_snapshots s
  left join lateral (select sum(x.amount) adjustments from factory_private.monthly_payroll_adjustments x where x.snapshot_id=s.id) a on true
  where p_month is null or s.payroll_month=date_trunc('month',p_month)::date
  order by s.payroll_month desc,s.employee_name_snapshot;
end $$;

create or replace function api.factory_inventory_quantities()
returns table(id uuid,material_code text,material_name text,category text,spec text,unit text,quantity_on_hand numeric,safety_stock numeric,stock_status text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select m.id,m.material_code,m.material_name,m.category,m.spec,m.unit,m.quantity_on_hand,m.safety_stock,
   case when m.quantity_on_hand<=m.safety_stock then '需补货' else '正常' end
  from factory_private.materials m order by m.category,m.material_name;
end $$;

create or replace function api.owner_factory_inventory_valuation()
returns table(id uuid,material_code text,material_name text,category text,cost_category text,spec text,unit text,quantity_on_hand numeric,moving_average_cost numeric,inventory_value numeric,safety_stock numeric,stock_status text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select m.id,m.material_code,m.material_name,m.category,m.cost_category,m.spec,m.unit,m.quantity_on_hand,m.moving_average_cost,
    round(m.quantity_on_hand*m.moving_average_cost,2),m.safety_stock,case when m.quantity_on_hand<=m.safety_stock then '需补货' else '正常' end
  from factory_private.materials m order by m.category,m.material_name;
end $$;

create or replace function api.owner_factory_inventory_movements(p_from date default null,p_to date default null)
returns table(id uuid,movement_date date,movement_type text,material_code text,material_name text,category text,spec text,unit text,quantity numeric,unit_price numeric,amount numeric,supplier_source text,order_no text,purpose text,handled_by text,note text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select x.id,x.movement_date,x.movement_type,m.material_code,m.material_name,m.category,m.spec,m.unit,x.quantity,x.unit_price,x.amount,x.supplier_source,w.order_no,x.purpose,x.handled_by,x.note
   from factory_private.inventory_movements x join factory_private.materials m on m.id=x.material_id left join factory_private.work_orders w on w.id=x.order_id
   where (p_from is null or x.movement_date>=p_from) and (p_to is null or x.movement_date<=p_to)
   order by x.movement_date desc,x.created_at desc;
end $$;

create or replace function api.factory_inventory_movements_safe(p_from date default null,p_to date default null)
returns table(id uuid,movement_date date,movement_type text,material_code text,material_name text,category text,spec text,unit text,quantity numeric,order_no text,purpose text,handled_by text,note text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select x.id,x.movement_date,x.movement_type,m.material_code,m.material_name,m.category,m.spec,m.unit,x.quantity,w.order_no,x.purpose,x.handled_by,x.note
   from factory_private.inventory_movements x join factory_private.materials m on m.id=x.material_id left join factory_private.work_orders w on w.id=x.order_id
   where (p_from is null or x.movement_date>=p_from) and (p_to is null or x.movement_date<=p_to)
   order by x.movement_date desc,x.created_at desc;
end $$;

create or replace function api.owner_factory_fixed_costs(p_month date default null)
returns table(id uuid,cost_month date,category text,amount numeric,item text,ownership text,note text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select f.id,f.cost_month,f.category,f.amount,f.item,f.ownership,f.note from public.fixed_costs f
   where f.ownership in ('工厂','共用') and (p_month is null or date_trunc('month',f.cost_month)::date=date_trunc('month',p_month)::date)
   order by f.cost_month desc,f.created_at desc;
end $$;

create or replace function api.owner_create_factory_work_order(
 p_order_no text,p_customer_project text,p_business_source text,p_order_date date,p_delivery_date date,p_order_amount numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_id uuid; v_duplicate boolean;
begin
 if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_order_amount<0 or p_order_no is null or length(btrim(p_order_no))=0 then raise exception using errcode='22023',message='factory_invalid_order'; end if;
 v_duplicate:=factory_private.claim_request('owner_create_factory_work_order',p_request_id,jsonb_build_object('order_no',p_order_no,'customer_project',p_customer_project,'business_source',p_business_source,'order_date',p_order_date,'delivery_date',p_delivery_date,'order_amount',p_order_amount,'note',p_note));
 if not v_duplicate then
   insert into factory_private.work_orders(order_no,customer_project,business_source,order_date,delivery_date,order_amount,note,created_by)
   values(p_order_no,p_customer_project,p_business_source,coalesce(p_order_date,current_date),p_delivery_date,p_order_amount,coalesce(p_note,''),custom_private.request_uid());
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_update_work_order(p_order_id uuid,p_process text,p_status text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_old factory_private.work_orders%rowtype; v_dup boolean;
begin
 if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if custom_private.request_role()='factory_manager' and (p_status in ('已完工','已结算') or p_process='已完工') then raise exception using errcode='42501',message='factory_owner_completion_required'; end if;
 if p_process not in ('未排产','到货待开料','开料','封边','排钻','加工','试装','打包','安装','已完工') or p_status not in ('待开工','进行中','暂停','已完工','已结算') then raise exception using errcode='22023',message='factory_invalid_status'; end if;
 v_dup:=factory_private.claim_request('factory_update_work_order',p_request_id,jsonb_build_object('order_id',p_order_id,'process',p_process,'status',p_status));
 if not v_dup then
  select * into v_old from factory_private.work_orders where id=p_order_id for update;
  if not found then raise exception using errcode='P0002',message='factory_order_not_found'; end if;
  update factory_private.work_orders set current_process=p_process,status=p_status,
    completed_at=case when p_status in ('已完工','已结算') then coalesce(completed_at,now()) else null end,updated_at=now()
    where id=p_order_id;
  insert into factory_private.work_order_status_history(order_id,old_status,new_status,old_process,new_process,changed_by,request_id)
    values(p_order_id,v_old.status,p_status,v_old.current_process,p_process,custom_private.request_uid(),p_request_id);
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.owner_record_factory_order_cost(p_order_id uuid,p_cost_category text,p_amount numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean;
begin
 if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_cost_category not in ('加工人工','外协','其他') or p_amount<=0 then raise exception using errcode='22023',message='factory_invalid_cost'; end if;
 v_dup:=factory_private.claim_request('owner_record_factory_order_cost',p_request_id,jsonb_build_object('order_id',p_order_id,'category',p_cost_category,'amount',p_amount,'note',p_note));
 if not v_dup then
  insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,note,created_by,request_id)
  values(p_order_id,p_cost_category,p_amount,'owner_entry',coalesce(p_note,''),custom_private.request_uid(),p_request_id);
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.owner_reverse_factory_order_cost(p_entry_id uuid,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_old factory_private.order_cost_entries%rowtype; v_dup boolean;
begin
 if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 v_dup:=factory_private.claim_request('owner_reverse_factory_order_cost',p_request_id,jsonb_build_object('entry_id',p_entry_id,'note',p_note));
 if not v_dup then
  select * into v_old from factory_private.order_cost_entries where id=p_entry_id for update;
  if not found or v_old.source_type<>'owner_entry' or v_old.reverses_entry_id is not null or exists(select 1 from factory_private.order_cost_entries x where x.reverses_entry_id=p_entry_id) then raise exception using errcode='22023',message='factory_entry_not_reversible'; end if;
  insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,source_id,reverses_entry_id,note,created_by,request_id)
  values(v_old.order_id,v_old.cost_category,-v_old.amount,'reversal',p_entry_id,p_entry_id,coalesce(p_note,''),custom_private.request_uid(),p_request_id);
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.owner_save_factory_employee(p_employee_id uuid,p_employee_name text,p_job text,p_pay_method text,p_pay_rate numeric,p_employment_status text,p_note text,p_effective_from date,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_id uuid; v_dup boolean;
begin
 if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_pay_rate<0 then raise exception using errcode='22023',message='factory_invalid_pay_rate'; end if;
 v_dup:=factory_private.claim_request('owner_save_factory_employee',p_request_id,jsonb_build_object('employee_id',p_employee_id,'name',p_employee_name,'job',p_job,'method',p_pay_method,'rate',p_pay_rate,'status',p_employment_status,'note',p_note,'effective_from',p_effective_from));
 if not v_dup then
  if p_employee_id is null then
   insert into factory_private.employees(employee_name,job,pay_method,pay_rate,employment_status,note,updated_by)
   values(p_employee_name,p_job,p_pay_method,p_pay_rate,p_employment_status,coalesce(p_note,''),custom_private.request_uid()) returning id into v_id;
  else
   update factory_private.employees set employee_name=p_employee_name,job=p_job,pay_method=p_pay_method,pay_rate=p_pay_rate,employment_status=p_employment_status,note=coalesce(p_note,''),updated_by=custom_private.request_uid(),updated_at=now()
    where id=p_employee_id returning id into v_id;
   if v_id is null then raise exception using errcode='P0002',message='factory_employee_not_found'; end if;
  end if;
  insert into factory_private.employee_rate_history(employee_id,effective_from,pay_method,pay_rate,employment_status,note,created_by)
  values(v_id,coalesce(p_effective_from,current_date),p_pay_method,p_pay_rate,p_employment_status,coalesce(p_note,''),custom_private.request_uid())
  on conflict(employee_id,effective_from) do update set pay_method=excluded.pay_method,pay_rate=excluded.pay_rate,employment_status=excluded.employment_status,note=excluded.note;
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_save_material(p_material_id uuid,p_material_code text,p_material_name text,p_category text,p_cost_category text,p_spec text,p_unit text,p_safety_stock numeric,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean;
begin
 if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_safety_stock<0 then raise exception using errcode='22023',message='factory_invalid_stock'; end if;
 v_dup:=factory_private.claim_request('factory_save_material',p_request_id,jsonb_build_object('id',p_material_id,'code',p_material_code,'name',p_material_name,'category',p_category,'cost_category',p_cost_category,'spec',p_spec,'unit',p_unit,'safety',p_safety_stock));
 if not v_dup then
  if p_material_id is null then
   insert into factory_private.materials(material_code,material_name,category,cost_category,spec,unit,safety_stock)
   values(p_material_code,p_material_name,p_category,p_cost_category,coalesce(p_spec,''),p_unit,p_safety_stock);
  else
   update factory_private.materials set material_code=p_material_code,material_name=p_material_name,category=p_category,cost_category=p_cost_category,spec=coalesce(p_spec,''),unit=p_unit,safety_stock=p_safety_stock,updated_at=now() where id=p_material_id;
   if not found then raise exception using errcode='P0002',message='factory_material_not_found'; end if;
  end if;
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_record_inventory_movement(p_movement_date date,p_movement_type text,p_material_id uuid,p_quantity numeric,p_unit_price numeric,p_supplier_source text,p_order_id uuid,p_purpose text,p_handled_by text,p_note text,p_reverses_movement_id uuid,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_mat factory_private.materials%rowtype; v_old factory_private.inventory_movements%rowtype; v_value numeric; v_cost numeric; v_amount numeric; v_movement_id uuid; v_issue_cost factory_private.order_cost_entries%rowtype; v_returned_qty numeric; v_reversed_amount numeric;
begin
 if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_quantity<=0 or p_unit_price<0 then raise exception using errcode='22023',message='factory_invalid_quantity'; end if;
 if p_movement_type not in ('入库','出库','退料','盘盈','盘亏') then raise exception using errcode='22023',message='factory_invalid_movement'; end if;
 if p_movement_type='出库' and p_order_id is null then raise exception using errcode='22023',message='factory_order_required'; end if;
 if p_movement_type='退料' and p_reverses_movement_id is null then raise exception using errcode='22023',message='factory_issue_required'; end if;
 v_dup:=factory_private.claim_request('factory_record_inventory_movement',p_request_id,jsonb_build_object('date',p_movement_date,'type',p_movement_type,'material',p_material_id,'qty',p_quantity,'price',p_unit_price,'supplier',p_supplier_source,'order',p_order_id,'purpose',p_purpose,'handled_by',p_handled_by,'note',p_note,'reverses',p_reverses_movement_id));
 if not v_dup then
  select * into v_mat from factory_private.materials where id=p_material_id for update;
  if not found then raise exception using errcode='P0002',message='factory_material_not_found'; end if;
  v_cost:=v_mat.moving_average_cost;
  v_amount:=0;
  if p_movement_type='入库' or p_movement_type='盘盈' then
    if p_movement_type='盘盈' and p_unit_price=0 then v_cost:=v_mat.moving_average_cost; else v_cost:=p_unit_price; end if;
    v_value:=v_mat.quantity_on_hand*v_mat.moving_average_cost+p_quantity*v_cost;
    update factory_private.materials set quantity_on_hand=quantity_on_hand+p_quantity,moving_average_cost=case when quantity_on_hand+p_quantity=0 then v_cost else v_value/(quantity_on_hand+p_quantity) end,updated_at=now() where id=p_material_id;
    v_amount:=round(p_quantity*v_cost,2);
  elsif p_movement_type='出库' or p_movement_type='盘亏' then
    if p_quantity>v_mat.quantity_on_hand then raise exception using errcode='22023',message='factory_insufficient_stock'; end if;
    v_amount:=round(p_quantity*v_cost,2);
    update factory_private.materials set quantity_on_hand=quantity_on_hand-p_quantity,updated_at=now() where id=p_material_id;
  else
    select * into v_old from factory_private.inventory_movements where id=p_reverses_movement_id and movement_type='出库' for update;
    if not found or v_old.material_id<>p_material_id or v_old.order_id is null or (p_order_id is not null and p_order_id<>v_old.order_id) then raise exception using errcode='22023',message='factory_invalid_return'; end if;
    select coalesce(sum(quantity),0) into v_returned_qty from factory_private.inventory_movements where movement_type='退料' and reverses_movement_id=v_old.id;
    if v_returned_qty+p_quantity>v_old.quantity then raise exception using errcode='22023',message='factory_invalid_return_quantity'; end if;
    select * into v_issue_cost from factory_private.order_cost_entries where source_type='inventory' and source_id=v_old.id;
    if not found then raise exception using errcode='22023',message='factory_issue_cost_missing'; end if;
    select coalesce(sum(-amount),0) into v_reversed_amount from factory_private.order_cost_entries where reverses_entry_id=v_issue_cost.id;
    v_cost:=v_old.unit_cost_snapshot;
    v_value:=v_mat.quantity_on_hand*v_mat.moving_average_cost+p_quantity*v_cost;
    update factory_private.materials set quantity_on_hand=quantity_on_hand+p_quantity,moving_average_cost=case when quantity_on_hand+p_quantity=0 then v_cost else v_value/(quantity_on_hand+p_quantity) end,updated_at=now() where id=p_material_id;
    v_amount:=least(round(p_quantity*v_cost,2),greatest(0,v_issue_cost.amount-v_reversed_amount));
  end if;
  insert into factory_private.inventory_movements(movement_date,movement_type,material_id,quantity,unit_price,amount,unit_cost_snapshot,supplier_source,order_id,purpose,handled_by,note,reverses_movement_id,recorded_by,request_id)
  values(coalesce(p_movement_date,current_date),p_movement_type,p_material_id,p_quantity,case when p_movement_type in ('出库','退料','盘亏') then v_cost else p_unit_price end,v_amount,v_cost,coalesce(p_supplier_source,''),case when p_movement_type='退料' then v_old.order_id else p_order_id end,coalesce(p_purpose,''),coalesce(p_handled_by,''),coalesce(p_note,''),p_reverses_movement_id,custom_private.request_uid(),p_request_id) returning id into v_movement_id;
  if p_movement_type='出库' then
    insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,source_id,note,created_by,request_id)
    values(p_order_id,v_mat.cost_category,v_amount,'inventory',v_movement_id,coalesce(p_purpose,''),custom_private.request_uid(),p_request_id);
  elsif p_movement_type='退料' then
    if v_reversed_amount+v_amount>v_issue_cost.amount then raise exception using errcode='22023',message='factory_return_cost_exceeds_issue'; end if;
    insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,source_id,reverses_entry_id,note,created_by,request_id)
    values(v_issue_cost.order_id,v_issue_cost.cost_category,-v_amount,'reversal',v_movement_id,v_issue_cost.id,coalesce(p_note,''),custom_private.request_uid(),p_request_id);
  end if;
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.factory_record_attendance(p_employee_id uuid,p_work_date date,p_job text,p_status text,p_hours numeric,p_work_content text,p_piece_quantity numeric,p_overtime_hours numeric,p_allocations jsonb,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_emp factory_private.employees%rowtype; v_effective_method text; v_effective_rate numeric; v_attendance_id uuid; v_allocation_id uuid; v_alloc jsonb; v_order_id uuid; v_hours numeric; v_pieces numeric; v_total_hours numeric; v_total_pieces numeric; v_amount numeric;
begin
 if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_hours<0 or p_piece_quantity<0 or p_overtime_hours<0 then raise exception using errcode='22023',message='factory_invalid_attendance'; end if;
 v_dup:=factory_private.claim_request('factory_record_attendance',p_request_id,jsonb_build_object('employee',p_employee_id,'date',p_work_date,'job',p_job,'status',p_status,'hours',p_hours,'content',p_work_content,'pieces',p_piece_quantity,'overtime',p_overtime_hours,'allocations',coalesce(p_allocations,'[]'::jsonb),'note',p_note));
 if not v_dup then
  select * into v_emp from factory_private.employees where id=p_employee_id and employment_status='在职' for update;
  if not found then raise exception using errcode='22023',message='factory_employee_inactive'; end if;
  select h.pay_method,h.pay_rate into v_effective_method,v_effective_rate from factory_private.employee_rate_history h
   where h.employee_id=p_employee_id and h.effective_from<=p_work_date order by h.effective_from desc limit 1;
  if found then v_emp.pay_method:=v_effective_method;v_emp.pay_rate:=v_effective_rate;end if;
  if jsonb_typeof(coalesce(p_allocations,'[]'::jsonb))<>'array' then raise exception using errcode='22023',message='factory_invalid_allocations'; end if;
  select coalesce(sum((x->>'hours')::numeric),0),coalesce(sum((x->>'piece_qty')::numeric),0) into v_total_hours,v_total_pieces from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) x;
  if v_emp.pay_method in ('日薪','计件') and p_status in ('出勤','加班') and jsonb_array_length(coalesce(p_allocations,'[]'::jsonb))=0 then raise exception using errcode='22023',message='factory_order_required'; end if;
  if v_emp.pay_method='日薪' and abs(v_total_hours-p_hours)>0.01 then raise exception using errcode='22023',message='factory_daily_hours_mismatch'; end if;
  if v_emp.pay_method='计件' and abs(v_total_pieces-p_piece_quantity)>0.001 then raise exception using errcode='22023',message='factory_piece_quantity_mismatch'; end if;
  if v_emp.pay_method='月薪' and jsonb_array_length(coalesce(p_allocations,'[]'::jsonb))>0 then raise exception using errcode='22023',message='factory_monthly_not_order_cost'; end if;
  insert into factory_private.attendance(employee_id,work_date,job,attendance_status,hours,work_content,piece_quantity,overtime_hours,note,recorded_by,request_id)
  values(p_employee_id,p_work_date,coalesce(p_job,''),p_status,p_hours,coalesce(p_work_content,''),p_piece_quantity,p_overtime_hours,coalesce(p_note,''),custom_private.request_uid(),p_request_id) returning id into v_attendance_id;
  for v_alloc in select value from jsonb_array_elements(coalesce(p_allocations,'[]'::jsonb)) loop
    v_order_id:=(v_alloc->>'order_id')::uuid; v_hours:=coalesce((v_alloc->>'hours')::numeric,0); v_pieces:=coalesce((v_alloc->>'piece_qty')::numeric,0);
    insert into factory_private.attendance_allocations(attendance_id,order_id,allocated_hours,piece_quantity) values(v_attendance_id,v_order_id,v_hours,v_pieces) returning id into v_allocation_id;
    if v_emp.pay_method='日薪' and p_status in ('出勤','加班') then v_amount:=round(v_emp.pay_rate*v_hours/nullif(p_hours,0),2);
    elsif v_emp.pay_method='计件' then v_amount:=round(v_emp.pay_rate*v_pieces,2);
    else v_amount:=0; end if;
    if v_amount<>0 then
      insert into factory_private.order_cost_entries(order_id,cost_category,amount,source_type,source_id,note,created_by,request_id)
      values(v_order_id,'加工人工',v_amount,'attendance',v_allocation_id,coalesce(p_work_content,''),custom_private.request_uid(),gen_random_uuid());
    end if;
  end loop;
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.owner_close_factory_payroll(p_month date,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_month date;
begin
 if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 v_month:=date_trunc('month',p_month)::date;
 v_dup:=factory_private.claim_request('owner_close_factory_payroll',p_request_id,jsonb_build_object('month',v_month));
 if not v_dup then
  insert into factory_private.monthly_payroll_snapshots(payroll_month,employee_id,employee_name_snapshot,pay_rate_snapshot,amount,created_by,request_id)
  select v_month,e.id,e.employee_name,coalesce(h.pay_rate,e.pay_rate),coalesce(h.pay_rate,e.pay_rate),custom_private.request_uid(),gen_random_uuid()
  from factory_private.employees e left join lateral (select x.pay_rate from factory_private.employee_rate_history x where x.employee_id=e.id and x.effective_from<=v_month order by x.effective_from desc limit 1) h on true
  where coalesce((select x.pay_method from factory_private.employee_rate_history x where x.employee_id=e.id and x.effective_from<=v_month order by x.effective_from desc limit 1),e.pay_method)='月薪' and e.employment_status='在职'
  on conflict(payroll_month,employee_id) do nothing;
 end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.owner_adjust_factory_payroll(p_snapshot_id uuid,p_amount numeric,p_note text,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean;
begin
 if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 if p_amount=0 then raise exception using errcode='22023',message='factory_invalid_adjustment'; end if;
 v_dup:=factory_private.claim_request('owner_adjust_factory_payroll',p_request_id,jsonb_build_object('snapshot',p_snapshot_id,'amount',p_amount,'note',p_note));
 if not v_dup then insert into factory_private.monthly_payroll_adjustments(snapshot_id,amount,note,created_by,request_id)
  values(p_snapshot_id,p_amount,coalesce(p_note,''),custom_private.request_uid(),p_request_id); end if;
 return jsonb_build_object('status','ok');
end $$;

create or replace function api.owner_factory_monthly_gross()
returns table(month date,factory_gross numeric,completed_order_count bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
 if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
 return query select date_trunc('month',w.completed_at)::date,
  coalesce(sum(coalesce(w.order_amount,0)-coalesce(c.cost_total,0)),0)::numeric,count(*)::bigint
 from factory_private.work_orders w
 left join lateral (select sum(x.amount) cost_total from factory_private.order_cost_entries x where x.order_id=w.id) c on true
 where w.completed_at is not null and w.status in ('已完工','已结算')
 group by date_trunc('month',w.completed_at)::date order by 1;
end $$;

create or replace function custom_private.read_owner_monthly_net_profit_factory()
returns table(month date,renovation_gross numeric,custom_gross numeric,factory_gross numeric,gross_total numeric,fixed_cost numeric,net_profit numeric,cumulative_net_profit numeric,custom_completed_order_count bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query
 with base as (select * from custom_private.read_owner_monthly_net_profit_step7()),
 fg as (select * from api.owner_factory_monthly_gross()),
 fp as (select s.payroll_month::date payroll_month,coalesce(sum(s.amount)+coalesce(sum(a.adjustment),0),0)::numeric amount
   from factory_private.monthly_payroll_snapshots s
   left join lateral (select sum(x.amount) adjustment from factory_private.monthly_payroll_adjustments x where x.snapshot_id=s.id) a on true
   group by s.payroll_month),
 months as (select b.month from base b union select f.month from fg f union select p.payroll_month from fp p),
 merged as (
  select m.month,coalesce(b.renovation_gross,0)::numeric renovation_gross,coalesce(b.custom_gross,0)::numeric custom_gross,
   (coalesce(b.factory_gross,0)+coalesce(f.factory_gross,0))::numeric factory_gross,
   (coalesce(b.gross_total,0)+coalesce(f.factory_gross,0))::numeric gross_total,
   (coalesce(b.fixed_cost,0)+coalesce(p.amount,0))::numeric fixed_cost,
   coalesce(b.custom_completed_order_count,0)::bigint custom_completed_order_count
  from months m left join base b using(month) left join fg f using(month) left join fp p on p.payroll_month=m.month)
 select x.month,x.renovation_gross,x.custom_gross,x.factory_gross,x.gross_total,x.fixed_cost,x.gross_total-x.fixed_cost,
  sum(x.gross_total-x.fixed_cost) over(order by x.month rows between unbounded preceding and current row),x.custom_completed_order_count
 from merged x order by x.month;
end $$;

create or replace function custom_private.read_owner_yearly_net_profit_factory()
returns table(year integer,renovation_gross numeric,custom_gross numeric,factory_gross numeric,gross_total numeric,fixed_cost numeric,net_profit numeric,custom_completed_order_count bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query select extract(year from m.month)::integer,coalesce(sum(m.renovation_gross),0)::numeric,
  coalesce(sum(m.custom_gross),0)::numeric,coalesce(sum(m.factory_gross),0)::numeric,coalesce(sum(m.gross_total),0)::numeric,
  coalesce(sum(m.fixed_cost),0)::numeric,coalesce(sum(m.net_profit),0)::numeric,coalesce(sum(m.custom_completed_order_count),0)::bigint
 from custom_private.read_owner_monthly_net_profit_factory() m group by extract(year from m.month);
end $$;

do $$
declare f record;
begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where (n.nspname='api' and p.proname in ('owner_factory_work_orders','owner_factory_order_cost_entries','factory_work_orders_safe','owner_factory_employees','factory_employees_safe','factory_attendance_safe','owner_factory_payroll','factory_inventory_quantities','owner_factory_inventory_valuation','owner_factory_inventory_movements','factory_inventory_movements_safe','owner_factory_fixed_costs','owner_create_factory_work_order','factory_update_work_order','owner_record_factory_order_cost','owner_reverse_factory_order_cost','owner_save_factory_employee','factory_save_material','factory_record_inventory_movement','factory_record_attendance','owner_close_factory_payroll','owner_adjust_factory_payroll','owner_factory_monthly_gross'))
     or (n.nspname='custom_private' and p.proname in ('read_owner_monthly_net_profit_factory','read_owner_yearly_net_profit_factory')) loop
   execute format('alter function %s owner to anju_custom_executor',f.sig);
   execute format('revoke all on function %s from public,anon',f.sig);
   execute format('grant execute on function %s to authenticated,anju_custom_executor',f.sig);
 end loop;
end $$;
revoke create on schema factory_private from anju_custom_executor;

create or replace view api.owner_monthly_net_profit with(security_invoker=false) as
 select * from custom_private.read_owner_monthly_net_profit_factory();
alter view api.owner_monthly_net_profit owner to anju_custom_executor;
revoke all on api.owner_monthly_net_profit from public,anon;
grant select on api.owner_monthly_net_profit to authenticated,anju_custom_executor;

create or replace view api.owner_yearly_net_profit with(security_invoker=false) as
 select * from custom_private.read_owner_yearly_net_profit_factory();
alter view api.owner_yearly_net_profit owner to anju_custom_executor;
revoke all on api.owner_yearly_net_profit from public,anon;
grant select on api.owner_yearly_net_profit to authenticated,anju_custom_executor;

notify pgrst,'reload schema';
commit;
