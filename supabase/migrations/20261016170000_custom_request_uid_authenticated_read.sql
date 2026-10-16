-- Allow security-invoker API views to resolve the caller's own UID.
-- The helper is SECURITY DEFINER, has a fixed search_path, and returns only
-- auth.uid(); it does not expose Auth user records or weaken table RLS.
begin;

grant usage on schema custom_private to authenticated;
grant execute on function custom_private.request_uid() to authenticated;

notify pgrst, 'reload schema';
commit;
