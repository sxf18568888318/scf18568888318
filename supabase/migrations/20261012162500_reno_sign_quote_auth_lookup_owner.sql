-- Run as the database owner: reno_sign_quote validates foreman role metadata
-- in auth.users. Its security-definer owner must be allowed to read that schema.
alter function api.reno_sign_quote(uuid,uuid,timestamptz,uuid) owner to postgres;
revoke all on function api.reno_sign_quote(uuid,uuid,timestamptz,uuid) from public, anon;
grant execute on function api.reno_sign_quote(uuid,uuid,timestamptz,uuid) to authenticated, anju_custom_executor;
notify pgrst, 'reload schema';
