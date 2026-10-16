-- The Supabase-managed auth schema is owned by supabase_admin. The project SQL
-- role cannot grant its schema USAGE to the dedicated custom RPC executor.
-- Route JWT identity reads through the existing narrowly scoped postgres-owned
-- request_uid() helper instead of resolving auth.uid() as the executor.
begin;

revoke all on function custom_private.request_uid() from public;
revoke all on function custom_private.request_uid() from anon;
revoke all on function custom_private.request_uid() from authenticated;
grant execute on function custom_private.request_uid() to anju_custom_executor;

do $migration$
declare
  r record;
  updated_count integer := 0;
begin
  for r in
    select p.oid, pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind = 'f'
      and n.nspname = 'custom_private'
      and p.proowner = 'anju_custom_executor'::regrole
      and position('auth.uid()' in lower(pg_get_functiondef(p.oid))) > 0
  loop
    execute replace(r.definition, 'auth.uid()', 'custom_private.request_uid()');
    updated_count := updated_count + 1;
  end loop;

end
$migration$;

-- Row-level policies for executor-owned writes must use the same bridge.
do $policies$
declare
  r record;
  statement text;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where 'anju_custom_executor' = any(roles)
      and (coalesce(qual, '') ilike '%auth.uid()%'
        or coalesce(with_check, '') ilike '%auth.uid()%')
  loop
    statement := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if r.qual is not null then
      statement := statement || format(' using (%s)', replace(r.qual, 'auth.uid()', 'custom_private.request_uid()'));
    end if;
    if r.with_check is not null then
      statement := statement || format(' with check (%s)', replace(r.with_check, 'auth.uid()', 'custom_private.request_uid()'));
    end if;
    execute statement;
  end loop;
end
$policies$;

notify pgrst, 'reload schema';
commit;
