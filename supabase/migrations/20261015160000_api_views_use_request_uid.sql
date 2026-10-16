-- Preserve existing API view projections and role filters while using the
-- project's authenticated identity helper instead of direct auth.uid() calls.
begin;

create or replace view api.factory_order_detail with (security_invoker=true) as
select id,order_no,customer_id,factory_manager_id,status,business_source,order_date,delivery_date,current_process,note
from public.factory_orders
where app.role()='owner'
   or (app.role()='factory_manager' and factory_manager_id=custom_private.request_uid());

create or replace view api.foreman_site_stages with (security_invoker=true) as
select st.id,st.site_id,st.stage_key,st.status,st.note,st.accepted_by,st.updated_by,st.updated_at
from public.site_stages st join public.sites s on s.id=st.site_id
where app.role()='owner'
   or (app.role()='foreman' and s.foreman_id=custom_private.request_uid());

create or replace view api.foreman_sites with (security_invoker=true) as
select id,customer_id,foreman_id,current_stage,created_at
from public.sites s
where app.role()='owner'
   or (app.role()='foreman' and foreman_id=custom_private.request_uid());

create or replace view api.my_customer_receivables with (security_invoker=true) as
select c.id as customer_id,c.name,c.community,c.owner_id,
       coalesce((select sum(pp.planned_amount) from public.payment_plans pp where pp.customer_id=c.id),0)::numeric as receivable,
       coalesce((select sum(p.amount) from public.payments p where p.customer_id=c.id),0)::numeric as received,
       greatest((coalesce((select sum(pp.planned_amount) from public.payment_plans pp where pp.customer_id=c.id),0)
              - coalesce((select sum(p.amount) from public.payments p where p.customer_id=c.id),0)),0)::numeric as outstanding
from public.customers c
where app.role()='owner'
   or (app.role()='designer' and c.owner_id=custom_private.request_uid());

create or replace view api.my_customers with (security_invoker=true) as
select id,business_line,name,phone,community,owner_id,status,created_at
from public.customers
where app.role()=any(array['owner','designer']::text[])
  and (app.role()='owner' or owner_id=custom_private.request_uid());

create or replace view api.my_quotes with (security_invoker=true) as
select q.id,q.customer_id,q.business_line,q.title,q.amount,q.status,q.created_by,q.created_at
from public.quotes q join public.customers c on c.id=q.customer_id
where app.role()='owner' or c.owner_id=custom_private.request_uid();

create or replace view api.my_site_stages with (security_invoker=true) as
select st.id,st.site_id,st.stage_key,st.status,st.note,st.accepted_by,st.updated_by,st.updated_at
from public.site_stages st join public.sites s on s.id=st.site_id
where app.role()='owner'
   or (app.role()='foreman' and s.foreman_id=custom_private.request_uid())
   or app.role()='factory_manager';

create or replace view api.my_sites with (security_invoker=true) as
select id,customer_id,foreman_id,current_stage,created_at
from public.sites s
where app.role()='owner'
   or (app.role()='foreman' and foreman_id=custom_private.request_uid())
   or app.role()='factory_manager';

commit;
