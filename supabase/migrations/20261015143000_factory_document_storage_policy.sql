begin;

-- Storage policies must not read factory_private tables as the caller.
-- Keep the metadata lookup behind a narrowly scoped SECURITY DEFINER helper.
create or replace function factory_private.document_path_allowed(p_name text,p_action text)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_order uuid;
begin
  if p_name is null or p_name like '%..%' or p_action not in ('read','write') then return false; end if;
  if split_part(p_name,'/',1)<>'factory' then return false; end if;
  begin v_order:=split_part(p_name,'/',2)::uuid; exception when others then return false; end;
  if p_action='read' then
    return exists(
      select 1 from factory_private.order_documents d
      where d.order_id=v_order and d.storage_path=p_name
        and factory_private.order_scope_allowed(d.order_id,'read')
    );
  end if;
  return factory_private.storage_path_allowed(p_name,'write');
end $$;
alter function factory_private.document_path_allowed(text,text) owner to postgres;
revoke all on function factory_private.document_path_allowed(text,text) from public,anon;
grant execute on function factory_private.document_path_allowed(text,text) to authenticated;

drop policy if exists factory_files_read on storage.objects;
create policy factory_files_read on storage.objects
  for select to authenticated
  using(bucket_id='factory-files' and factory_private.document_path_allowed(name,'read'));

drop policy if exists factory_files_insert on storage.objects;
create policy factory_files_insert on storage.objects
  for insert to authenticated
  with check(bucket_id='factory-files' and factory_private.document_path_allowed(name,'write'));

notify pgrst,'reload schema';
commit;
