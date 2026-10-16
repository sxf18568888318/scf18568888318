-- Owner-only read adapter for existing factory order cash entries.
-- This migration adds no data and does not change the cash-entry write RPC.
begin;

create or replace function api.owner_factory_cash_ledger()
returns table(
  id uuid,
  order_id uuid,
  entry_kind text,
  entry_date date,
  amount numeric,
  method text,
  counterparty text,
  note text,
  order_no text,
  customer_project text
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  perform custom_private.require_roles(array['owner']);
  return query
    select x.id, x.order_id, x.entry_kind, x.entry_date, x.amount,
           x.method, x.counterparty, x.note, w.order_no, w.customer_project
      from factory_private.order_cash_entries x
      join factory_private.work_orders w on w.id=x.order_id
     order by x.entry_date desc, x.created_at desc;
end
$$;

alter function api.owner_factory_cash_ledger() owner to anju_custom_executor;
revoke all on function api.owner_factory_cash_ledger() from public, anon;
grant execute on function api.owner_factory_cash_ledger() to authenticated;

notify pgrst, 'reload schema';
commit;
