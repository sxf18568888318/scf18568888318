-- Expose production progress for quotes whose customer is in the current user's scope.
begin;

create or replace view api.custom_factory_progress as
select f.custom_quote_id as quote_id,
       f.customer_id,
       f.status,
       f.current_process,
       f.order_date,
       f.delivery_date,
       f.completed_at
  from public.factory_orders f
 where f.custom_quote_id is not null
   and custom_private.customer_allowed(f.customer_id);

alter view api.custom_factory_progress owner to anju_custom_executor;
revoke all on api.custom_factory_progress from public, anon;
grant select on api.custom_factory_progress to authenticated;
notify pgrst, 'reload schema';

commit;
