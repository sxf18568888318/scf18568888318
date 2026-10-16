-- Add the already-calculated landed line value to the owner-only purchase view.
-- This is a projection-only change: no purchase, allocation, or stock data is updated.
begin;

drop view if exists api.owner_custom_purchase_lines;

create or replace function custom_private.read_owner_custom_purchase_lines_step7()
returns table(
 id uuid,
 purchase_order_id uuid,
 board_id uuid,
 hardware_id uuid,
 temporary_item boolean,
 item_name text,
 brand text,
 spec text,
 catalog_snapshot jsonb,
 unit text,
 quantity numeric,
 purchase_unit_price numeric,
 line_amount numeric,
 landed_amount numeric,
 declared_amount numeric,
 amount_mismatch boolean,
 note text
)
language plpgsql stable security definer set search_path='' as $$
begin
 perform custom_private.require_roles(array['owner']);
 return query
 select l.id,l.purchase_order_id,l.board_id,l.hardware_id,l.temporary_item,
        l.item_name,l.brand,l.spec,l.catalog_snapshot,l.unit,l.quantity,
        l.purchase_unit_price,l.line_amount,l.landed_amount,l.declared_amount,
        l.line_amount<>l.declared_amount,l.note
 from public.custom_purchase_lines l;
end
$$;
alter function custom_private.read_owner_custom_purchase_lines_step7() owner to anju_custom_executor;

create view api.owner_custom_purchase_lines with(security_invoker=false) as
select * from custom_private.read_owner_custom_purchase_lines_step7();
alter view api.owner_custom_purchase_lines owner to anju_custom_executor;
revoke all on api.owner_custom_purchase_lines from public,anon;
grant select on api.owner_custom_purchase_lines to authenticated;
revoke all on function custom_private.read_owner_custom_purchase_lines_step7() from public,anon;
grant execute on function custom_private.read_owner_custom_purchase_lines_step7() to anju_custom_executor;
grant execute on function custom_private.read_owner_custom_purchase_lines_step7() to authenticated;

notify pgrst,'reload schema';
commit;
