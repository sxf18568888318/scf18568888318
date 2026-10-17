begin;

-- SECURITY DEFINER cash ledger RPCs execute as this role and need only to
-- read linked receipt metadata and insert the metadata for new uploads.
revoke all on factory_private.order_cash_entry_documents from public,anon,authenticated;
grant select,insert on factory_private.order_cash_entry_documents to anju_custom_executor;

commit;
