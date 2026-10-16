begin;

create or replace function factory_private.purchase_cost_document_path_allowed(p_name text)
returns boolean language plpgsql stable security definer set search_path=''
as $$ begin
  if p_name is null or p_name like '%..%' or split_part(p_name,'/',1)<>'factory' then return false; end if;
  return exists(
    select 1 from factory_private.order_purchase_cost_documents d
    join factory_private.order_purchase_costs p on p.id=d.purchase_cost_id
    where d.storage_path=p_name and factory_private.order_scope_allowed(p.order_id,'read')
  );
end $$;
alter function factory_private.purchase_cost_document_path_allowed(text) owner to postgres;
revoke all on function factory_private.purchase_cost_document_path_allowed(text) from public,anon;
grant execute on function factory_private.purchase_cost_document_path_allowed(text) to authenticated;

drop policy if exists factory_purchase_cost_files_read on storage.objects;
create policy factory_purchase_cost_files_read on storage.objects for select to authenticated
  using(bucket_id='factory-files' and factory_private.purchase_cost_document_path_allowed(name));

notify pgrst, 'reload schema';
commit;
