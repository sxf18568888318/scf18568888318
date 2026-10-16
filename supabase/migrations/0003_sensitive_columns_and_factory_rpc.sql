-- 工厂端不能通过原表绕过列级脱敏。原表撤销给 authenticated，工厂端通过角色视图和 RPC 访问。
revoke all on public.factory_orders, public.factory_employees from anon, authenticated;

drop view if exists api.factory_order_detail;
create view api.factory_order_detail as
select id, order_no, customer_id, factory_manager_id, status, business_source, order_date,
  delivery_date, current_process, board_cost, edge_cost, hardware_cost, processing_labor_cost,
  outsourcing_cost, other_cost, note
from public.factory_orders
where app.role() in ('owner','factory_manager')
  and (app.role()='owner' or factory_manager_id=auth.uid());

create or replace view api.owner_factory_finance as
select id, order_no, customer_id, business_source, order_date, delivery_date, current_process, status,
  order_amount, board_cost, edge_cost, hardware_cost, processing_labor_cost, outsourcing_cost, other_cost,
  (board_cost + edge_cost + hardware_cost + processing_labor_cost + outsourcing_cost + other_cost) as cost_total,
  case when order_amount is null then null else order_amount - (board_cost + edge_cost + hardware_cost + processing_labor_cost + outsourcing_cost + other_cost) end as gross_profit,
  case when order_amount is null or order_amount=0 then null else (order_amount - (board_cost + edge_cost + hardware_cost + processing_labor_cost + outsourcing_cost + other_cost)) / order_amount end as gross_margin,
  note
from public.factory_orders
where app.role()='owner';

create or replace view api.factory_employees_safe as
select id, employee_name, job, pay_method, employment_status, note, auth_user_id, created_at
from public.factory_employees
where app.role() in ('owner','factory_manager');

create or replace function api.factory_create_order(
  p_order_no text, p_customer_id uuid, p_business_source text, p_order_date date,
  p_delivery_date date, p_factory_manager_id uuid, p_current_process text default '未排产',
  p_status text default '待开工', p_note text default ''
) returns uuid
language plpgsql security definer set search_path = pg_catalog, public, app, api
as $$
declare new_id uuid;
begin
  if app.role() not in ('owner','factory_manager') then raise exception 'forbidden'; end if;
  if app.role()='factory_manager' and p_factory_manager_id <> auth.uid() then raise exception 'forbidden'; end if;
  insert into public.factory_orders(order_no,customer_id,factory_manager_id,business_source,order_date,delivery_date,current_process,status,note)
  values(p_order_no,p_customer_id,p_factory_manager_id,p_business_source,p_order_date,p_delivery_date,p_current_process,p_status,p_note)
  returning id into new_id;
  return new_id;
end $$;

create or replace function api.factory_update_order(
  p_order_id uuid, p_current_process text, p_status text,
  p_board_cost numeric, p_edge_cost numeric, p_hardware_cost numeric,
  p_processing_labor_cost numeric, p_outsourcing_cost numeric, p_other_cost numeric,
  p_note text default ''
) returns void
language plpgsql security definer set search_path = pg_catalog, public, app, api
as $$
begin
  if app.role() not in ('owner','factory_manager') then raise exception 'forbidden'; end if;
  update public.factory_orders
  set current_process=p_current_process,status=p_status,board_cost=coalesce(p_board_cost,0),edge_cost=coalesce(p_edge_cost,0),
      hardware_cost=coalesce(p_hardware_cost,0),processing_labor_cost=coalesce(p_processing_labor_cost,0),
      outsourcing_cost=coalesce(p_outsourcing_cost,0),other_cost=coalesce(p_other_cost,0),note=coalesce(p_note,'')
  where id=p_order_id and (app.role()='owner' or factory_manager_id=auth.uid());
  if not found then raise exception 'not_found_or_forbidden'; end if;
end $$;

create or replace function api.owner_set_order_amount(p_order_id uuid, p_order_amount numeric)
returns void language plpgsql security definer set search_path = pg_catalog, public, app, api
as $$
begin
  if app.role() <> 'owner' then raise exception 'forbidden'; end if;
  update public.factory_orders set order_amount=coalesce(p_order_amount,0) where id=p_order_id;
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function api.owner_upsert_employee(
  p_employee_id uuid, p_employee_name text, p_job text, p_pay_method text,
  p_pay_rate numeric, p_employment_status text, p_note text default '', p_auth_user_id uuid default null
) returns uuid language plpgsql security definer set search_path = pg_catalog, public, app, api
as $$
declare out_id uuid;
begin
  if app.role() <> 'owner' then raise exception 'forbidden'; end if;
  if p_employee_id is null then
    insert into public.factory_employees(employee_name,job,pay_method,pay_rate,employment_status,note,auth_user_id,created_by)
    values(p_employee_name,p_job,p_pay_method,p_pay_rate,p_employment_status,coalesce(p_note,''),p_auth_user_id,auth.uid()) returning id into out_id;
  else
    update public.factory_employees set employee_name=p_employee_name,job=p_job,pay_method=p_pay_method,pay_rate=p_pay_rate,
      employment_status=p_employment_status,note=coalesce(p_note,''),auth_user_id=p_auth_user_id where id=p_employee_id returning id into out_id;
    if out_id is null then raise exception 'not_found'; end if;
  end if;
  return out_id;
end $$;

create or replace function api.factory_record_attendance(
  p_employee_id uuid, p_work_date date, p_job text, p_status text, p_hours numeric,
  p_work_content text, p_piece_quantity numeric, p_overtime_hours numeric, p_note text default ''
) returns uuid language plpgsql security definer set search_path = pg_catalog, public, app, api
as $$
declare out_id uuid;
begin
  if app.role() not in ('owner','factory_manager') then raise exception 'forbidden'; end if;
  insert into public.attendance(employee_id,work_date,job,status,hours,work_content,piece_quantity,overtime_hours,recorded_by,note)
  values(p_employee_id,p_work_date,p_job,p_status,coalesce(p_hours,0),coalesce(p_work_content,''),coalesce(p_piece_quantity,0),coalesce(p_overtime_hours,0),auth.uid(),coalesce(p_note,''))
  returning id into out_id;
  return out_id;
end $$;

create or replace function api.factory_record_inventory(
  p_transaction_date date, p_transaction_type text, p_material_code text, p_material_name text,
  p_category text, p_spec text, p_unit text, p_quantity numeric, p_unit_price numeric,
  p_supplier_source text, p_related_order text, p_purpose text, p_handled_by text, p_note text default ''
) returns uuid language plpgsql security definer set search_path = pg_catalog, public, app, api
as $$
declare out_id uuid;
begin
  if app.role() not in ('owner','factory_manager') then raise exception 'forbidden'; end if;
  insert into public.inventory_transactions(transaction_date,transaction_type,material_code,material_name,category,spec,unit,quantity,unit_price,supplier_source,related_order,purpose,handled_by,note,created_by)
  values(coalesce(p_transaction_date,current_date),p_transaction_type,p_material_code,p_material_name,p_category,coalesce(p_spec,''),p_unit,coalesce(p_quantity,0),coalesce(p_unit_price,0),coalesce(p_supplier_source,''),coalesce(p_related_order,''),coalesce(p_purpose,''),coalesce(p_handled_by,''),coalesce(p_note,''),auth.uid())
  returning id into out_id;
  return out_id;
end $$;

grant execute on function api.factory_create_order(text,uuid,text,date,date,uuid,text,text,text) to authenticated;
grant execute on function api.factory_update_order(uuid,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text) to authenticated;
grant execute on function api.owner_set_order_amount(uuid,numeric) to authenticated;
grant execute on function api.owner_upsert_employee(uuid,text,text,text,numeric,text,text,uuid) to authenticated;
grant execute on function api.factory_record_attendance(uuid,date,text,text,numeric,text,numeric,numeric,text) to authenticated;
grant execute on function api.factory_record_inventory(date,text,text,text,text,text,text,numeric,numeric,text,text,text,text,text) to authenticated;
