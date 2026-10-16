-- These SECURITY DEFINER functions read auth.users for role assignment.
-- Keep their function bodies, role checks, and EXECUTE grants unchanged;
-- use a database owner that can read auth metadata.
begin;

alter function api.factory_assignment_users() owner to postgres;
alter function api.owner_assign_factory_work_order(uuid,uuid,uuid,text,text,uuid) owner to postgres;
alter function api.factory_record_attendance(uuid,date,text,text,numeric,text,numeric,numeric,text) owner to postgres;
alter function api.factory_record_attendance(uuid,date,text,text,numeric,text,numeric,numeric,jsonb,text,uuid) owner to postgres;
alter function api.reno_sign_quote(uuid,uuid,timestamptz,uuid) owner to postgres;

commit;
