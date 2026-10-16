-- Add line-level source traceability to the factory BOM projection without
-- exposing any quote or cost amounts. The copied order rows remain independent.
begin;

grant usage,create on schema custom_private to anju_custom_executor;

alter table public.hardware_bom_items
  drop constraint if exists hardware_bom_items_unit_check;
alter table public.hardware_bom_items
  add constraint hardware_bom_items_unit_check
  check(unit in ('个','副','套','米','张'));

drop view if exists api.custom_order_bom_factory;

create or replace function custom_private.read_custom_order_bom_factory_v2()
returns table(
  item_kind text,
  id uuid,
  factory_order_id uuid,
  source_item_id uuid,
  customer_id uuid,
  catalog_id uuid,
  item_name text,
  brand text,
  unit text,
  quantity numeric,
  thickness_mm numeric,
  color_name text,
  color_code text,
  finish_process text,
  edge_process text,
  edge_length_m numeric,
  space text,
  part_use text
)
language plpgsql stable security definer set search_path='' as $$
begin
  perform custom_private.require_roles(array['owner','factory_manager']);
  return query
    select 'board'::text,b.id,b.factory_order_id,b.source_item_id,b.customer_id,
      b.board_id,b.board_name,b.brand,b.unit,b.quantity,b.thickness_mm,b.color_name,
      b.color_code,b.finish_process,b.edge_process,b.edge_length_m,b.space,b.part_use
    from public.board_bom_items b
    where b.factory_order_id is not null
    union all
    select 'hardware'::text,h.id,h.factory_order_id,h.source_item_id,h.customer_id,
      h.hardware_id,h.hardware_name,h.brand,h.unit,h.quantity,null::numeric,
      ''::text,''::text,''::text,'无'::text,0::numeric,h.use_location,h.spec
    from public.hardware_bom_items h
    where h.factory_order_id is not null;
end;
$$;
alter function custom_private.read_custom_order_bom_factory_v2() owner to anju_custom_executor;

create view api.custom_order_bom_factory with(security_invoker=false)
as select * from custom_private.read_custom_order_bom_factory_v2();
alter view api.custom_order_bom_factory owner to anju_custom_executor;
revoke all on api.custom_order_bom_factory from public,anon;
grant select on api.custom_order_bom_factory to authenticated;
revoke all on function custom_private.read_custom_order_bom_factory_v2() from public,anon,authenticated;
grant execute on function custom_private.read_custom_order_bom_factory_v2() to authenticated,anju_custom_executor;

notify pgrst,'reload schema';
commit;
