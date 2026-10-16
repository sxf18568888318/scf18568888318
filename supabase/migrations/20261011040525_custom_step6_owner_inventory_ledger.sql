begin;

-- Owners can inspect the full stock ledger and moving-average valuation.
-- The view is a fixed projection and is guarded by a private role check.
create or replace function custom_private.read_owner_custom_inventory_transactions()
returns table(
 id uuid,catalog_kind text,catalog_id uuid,item_name text,transaction_type text,
 transaction_date date,quantity numeric,unit text,factory_order_id uuid,
 purchase_line_id uuid,source_transaction_id uuid,unit_cost numeric,total_cost numeric,note text
)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query
 select t.id,t.catalog_kind,t.catalog_id,
   case when t.catalog_kind='board' then b.material_name else h.hardware_name end,
   t.transaction_type,t.transaction_date,t.quantity,t.unit,t.factory_order_id,
   t.purchase_line_id,t.source_transaction_id,t.unit_cost,t.total_cost,t.note
 from public.custom_inventory_transactions t
 left join public.board_catalog b on t.catalog_kind='board' and b.id=t.catalog_id
 left join public.hardware_catalog h on t.catalog_kind='hardware' and h.id=t.catalog_id
 order by t.transaction_date desc,t.created_at desc;
end $$;
alter function custom_private.read_owner_custom_inventory_transactions() owner to anju_custom_executor;
revoke all on function custom_private.read_owner_custom_inventory_transactions() from public,anon,authenticated;
grant execute on function custom_private.read_owner_custom_inventory_transactions() to anju_custom_executor;
grant execute on function custom_private.read_owner_custom_inventory_transactions() to authenticated;

drop view if exists api.owner_custom_inventory_transactions;
create view api.owner_custom_inventory_transactions with(security_invoker=false) as
 select * from custom_private.read_owner_custom_inventory_transactions();
alter view api.owner_custom_inventory_transactions owner to anju_custom_executor;
revoke all on api.owner_custom_inventory_transactions from public,anon;
grant select on api.owner_custom_inventory_transactions to authenticated;

-- Factory material selection uses catalog labels and units only.
create or replace function custom_private.read_custom_catalog_factory()
returns table(catalog_kind text,catalog_id uuid,item_name text,unit text,status text)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner','factory_manager']);
 return query
 select 'board'::text,b.id,b.material_name,
   case when b.pricing_method='按㎡' then '㎡' when b.pricing_method='按延米' then '延米' else '张' end,
   b.status from public.board_catalog b
 union all
 select 'hardware'::text,h.id,h.hardware_name,h.unit,h.status from public.hardware_catalog h;
end $$;
alter function custom_private.read_custom_catalog_factory() owner to anju_custom_executor;
revoke all on function custom_private.read_custom_catalog_factory() from public,anon,authenticated;
grant execute on function custom_private.read_custom_catalog_factory() to anju_custom_executor;
grant execute on function custom_private.read_custom_catalog_factory() to authenticated;
drop view if exists api.custom_catalog_factory;
create view api.custom_catalog_factory with(security_invoker=false) as
 select * from custom_private.read_custom_catalog_factory();
alter view api.custom_catalog_factory owner to anju_custom_executor;
revoke all on api.custom_catalog_factory from public,anon;
grant select on api.custom_catalog_factory to authenticated;

-- Factory write endpoints acknowledge success only. The factory can submit
-- quantities or an expense value but never receives cost or inventory IDs.
create or replace function api.custom_material_issue(
 p_order_id uuid,p_kind text,p_catalog_id uuid,p_quantity numeric,p_unit text,
 p_date date,p_request_id uuid default null
) returns jsonb language sql security invoker set search_path='' as $$
 select case when app.role()='factory_manager'
   then jsonb_build_object('status',custom_private.material_issue(p_order_id,p_kind,p_catalog_id,p_quantity,p_unit,p_date,p_request_id)->>'status')
   else custom_private.material_issue(p_order_id,p_kind,p_catalog_id,p_quantity,p_unit,p_date,p_request_id)
 end
$$;
create or replace function api.custom_material_return(
 p_source_transaction_id uuid,p_quantity numeric,p_date date,p_request_id uuid default null
) returns jsonb language sql security invoker set search_path='' as $$
 select case when app.role()='factory_manager'
   then jsonb_build_object('status',custom_private.material_return(p_source_transaction_id,p_quantity,p_date,p_request_id)->>'status')
   else custom_private.material_return(p_source_transaction_id,p_quantity,p_date,p_request_id)
 end
$$;
create or replace function api.custom_factory_record_cost(
 p_order_id uuid,p_category text,p_quantity numeric,p_unit text,p_unit_cost numeric,
 p_note text,p_request_id uuid default null
) returns jsonb language sql security invoker set search_path='' as $$
 select case when app.role()='factory_manager'
   then jsonb_build_object('status',custom_private.factory_record_cost(p_order_id,p_category,p_quantity,p_unit,p_unit_cost,p_note,p_request_id)->>'status')
   else custom_private.factory_record_cost(p_order_id,p_category,p_quantity,p_unit,p_unit_cost,p_note,p_request_id)
 end
$$;

revoke all on function api.custom_material_issue(uuid,text,uuid,numeric,text,date,uuid) from public,anon;
revoke all on function api.custom_material_return(uuid,numeric,date,uuid) from public,anon;
revoke all on function api.custom_factory_record_cost(uuid,text,numeric,text,numeric,text,uuid) from public,anon;
grant execute on function api.custom_material_issue(uuid,text,uuid,numeric,text,date,uuid) to authenticated;
grant execute on function api.custom_material_return(uuid,numeric,date,uuid) to authenticated;
grant execute on function api.custom_factory_record_cost(uuid,text,numeric,text,numeric,text,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
