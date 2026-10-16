-- Factory labor is shared monthly overhead. Attendance no longer needs a
-- customer/order allocation and must never create per-order labor cost rows.
begin;

create or replace function api.factory_record_attendance(
  p_employee_id uuid,p_work_date date,p_job text,p_status text,p_hours numeric,
  p_work_content text,p_piece_quantity numeric,p_overtime_hours numeric,
  p_allocations jsonb,p_note text,p_request_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare v_dup boolean; v_emp factory_private.employees%rowtype;
begin
  if custom_private.request_role() not in ('owner','factory_manager') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  if p_request_id is null or p_work_date is null or p_hours<0 or p_piece_quantity<0 or p_overtime_hours<0
     or p_status not in ('出勤','请假','旷工','加班','休息') then
    raise exception using errcode='22023',message='factory_invalid_attendance';
  end if;
  if jsonb_typeof(coalesce(p_allocations,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_allocations,'[]'::jsonb))>0 then
    raise exception using errcode='22023',message='factory_labor_is_monthly_overhead';
  end if;
  v_dup:=factory_private.claim_request('factory_record_attendance',p_request_id,
    jsonb_build_object('employee',p_employee_id,'date',p_work_date,'job',p_job,'status',p_status,
      'hours',p_hours,'content',p_work_content,'pieces',p_piece_quantity,'overtime',p_overtime_hours,
      'allocations','[]'::jsonb,'note',p_note));
  if not v_dup then
    select * into v_emp from factory_private.employees where id=p_employee_id and employment_status='在职' for update;
    if not found then raise exception using errcode='22023',message='factory_employee_inactive'; end if;
    insert into factory_private.attendance(employee_id,work_date,job,attendance_status,hours,work_content,
      piece_quantity,overtime_hours,note,recorded_by,request_id)
    values(p_employee_id,p_work_date,coalesce(p_job,''),p_status,p_hours,coalesce(p_work_content,''),
      p_piece_quantity,p_overtime_hours,coalesce(p_note,''),custom_private.request_uid(),p_request_id);
  end if;
  return jsonb_build_object('status','ok');
end
$$;
alter function api.factory_record_attendance(uuid,date,text,text,numeric,text,numeric,numeric,jsonb,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_record_attendance(uuid,date,text,text,numeric,text,numeric,numeric,jsonb,text,uuid) from public,anon;
grant execute on function api.factory_record_attendance(uuid,date,text,text,numeric,text,numeric,numeric,jsonb,text,uuid) to authenticated;

create or replace function api.owner_factory_payroll(p_month date default null)
returns table(payroll_month date,employee_name text,pay_method text,amount numeric,source text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query
  with monthly as (
    select s.payroll_month::date payroll_month,s.employee_id,s.employee_name_snapshot employee_name,
           '月薪'::text pay_method,(s.amount+coalesce(a.adjustments,0))::numeric amount,'固定人工'::text source
    from factory_private.monthly_payroll_snapshots s
    left join lateral (select sum(x.amount) adjustments from factory_private.monthly_payroll_adjustments x where x.snapshot_id=s.id) a on true
    where p_month is null or s.payroll_month=date_trunc('month',p_month)::date
  ), attendance_rates as (
    select a.work_date,e.id employee_id,e.employee_name,h.pay_method,h.pay_rate,a.attendance_status,a.hours,
           a.piece_quantity
    from factory_private.attendance a
    join factory_private.employees e on e.id=a.employee_id
    cross join lateral (
      select x.pay_method,x.pay_rate from factory_private.employee_rate_history x
      where x.employee_id=e.id and x.effective_from<=a.work_date
      order by x.effective_from desc limit 1
    ) h
    where h.pay_method in ('日薪','计件')
      and (p_month is null or date_trunc('month',a.work_date)::date=date_trunc('month',p_month)::date)
  ), variable_monthly as (
    select date_trunc('month',work_date)::date payroll_month,employee_id,employee_name,pay_method,
      sum(case when pay_method='日薪' and attendance_status in ('出勤','加班') then pay_rate
               when pay_method='计件' and attendance_status in ('出勤','加班') then pay_rate*piece_quantity
               else 0 end)::numeric amount,
      case pay_method when '日薪' then '固定人工·按日薪×出勤天数'
                      else '固定人工·按计件单价×数量' end::text source
    from attendance_rates group by date_trunc('month',work_date)::date,employee_id,employee_name,pay_method
  )
  select * from monthly union all select * from variable_monthly
  order by payroll_month desc,employee_name;
end
$$;
alter function api.owner_factory_payroll(date) owner to anju_custom_executor;
revoke all on function api.owner_factory_payroll(date) from public,anon;
grant execute on function api.owner_factory_payroll(date) to authenticated;

create or replace function custom_private.read_owner_monthly_net_profit_factory()
returns table(month date,renovation_gross numeric,custom_gross numeric,factory_gross numeric,
              gross_total numeric,fixed_cost numeric,net_profit numeric,
              cumulative_net_profit numeric,custom_completed_order_count bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner']);
  return query
  with base as (select * from custom_private.read_owner_monthly_net_profit_step7()),
  fg as (select * from api.owner_factory_monthly_gross()),
  fp as (select date_trunc('month',p.payroll_month)::date payroll_month,coalesce(sum(p.amount),0)::numeric amount
         from api.owner_factory_payroll(null) p group by date_trunc('month',p.payroll_month)::date),
  months as (select b.month from base b union select f.month from fg f union select p.payroll_month from fp p),
  merged as (
    select m.month,coalesce(b.renovation_gross,0)::numeric renovation_gross,
      coalesce(b.custom_gross,0)::numeric custom_gross,
      (coalesce(b.factory_gross,0)+coalesce(f.factory_gross,0))::numeric factory_gross,
      (coalesce(b.gross_total,0)+coalesce(f.factory_gross,0))::numeric gross_total,
      (coalesce(b.fixed_cost,0)+coalesce(p.amount,0))::numeric fixed_cost,
      coalesce(b.custom_completed_order_count,0)::bigint custom_completed_order_count
    from months m left join base b using(month) left join fg f using(month)
      left join fp p on p.payroll_month=m.month
  )
  select x.month,x.renovation_gross,x.custom_gross,x.factory_gross,x.gross_total,x.fixed_cost,
    x.gross_total-x.fixed_cost,
    sum(x.gross_total-x.fixed_cost) over(order by x.month rows between unbounded preceding and current row),
    x.custom_completed_order_count
  from merged x order by x.month;
end
$$;
alter function custom_private.read_owner_monthly_net_profit_factory() owner to anju_custom_executor;
revoke all on function custom_private.read_owner_monthly_net_profit_factory() from public,anon,authenticated;
grant execute on function custom_private.read_owner_monthly_net_profit_factory() to authenticated;

notify pgrst,'reload schema';
commit;
