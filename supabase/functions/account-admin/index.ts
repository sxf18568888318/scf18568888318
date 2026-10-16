import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { isOwnerCaller } from './authz.mjs';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const roles = new Set(['owner', 'designer', 'foreman', 'factory_manager']);
const validLogin = (v: string) => /^yj18568888318-[0-9]{2,}$/.test(v);

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const authorization = req.headers.get('Authorization') || '';
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const callerClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  const { data: callerData, error: callerError } = await callerClient.auth.getUser();
  if (callerError || !callerData.user) return json({ error: 'invalid_session' }, 401);
  const callerId = callerData.user.id;
  const isOwner = await isOwnerCaller(callerId, async (id) => {
    const { data, error } = await admin.from('profiles').select('role').eq('id', id).maybeSingle();
    if (error) throw error;
    return data?.role;
  });
  if (!isOwner) return json({ error: 'owner_required' }, 403);
  try {
    const { action, payload = {} } = await req.json();
    const fail = (message: string, status = 400) => json({ error: message }, status);
    const findProfile = async (id: string) => {
      const [{ data: authData, error: authError }, { data: profile, error: profileError }] = await Promise.all([
        admin.auth.admin.getUserById(id), admin.from('profiles').select('id,display_name,role').eq('id', id).maybeSingle()
      ]);
      if (authError || profileError || !authData.user || !profile) throw new Error('account_not_found');
      return { auth: authData.user, profile };
    };
    const setRole = async (id: string, role: string) => {
      if (!roles.has(role)) throw new Error('invalid_role');
      const { auth, profile } = await findProfile(id);
      if (profile.role === 'owner' && role !== 'owner') {
        const { count } = await admin.from('profiles').select('id', { count: 'exact', head: true }).eq('role', 'owner');
        if ((count || 0) <= 1) throw new Error('last_owner');
      }
      const { error: updateAuthError } = await admin.auth.admin.updateUserById(id, { app_metadata: { ...auth.app_metadata, role } });
      if (updateAuthError) throw updateAuthError;
      const { error } = await admin.from('profiles').update({ role }).eq('id', id);
      if (error) throw error;
      return { id, display_name: profile.display_name, role };
    };
    if (action === 'list') {
      const [{ data: profiles, error: pErr }, { data: aliases, error: aErr }, { data: users, error: uErr }] = await Promise.all([
        admin.from('profiles').select('id,display_name,role').order('display_name'),
        admin.from('auth_login_aliases').select('user_id,login_name'),
        admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
      ]);
      if (pErr || aErr || uErr) throw pErr || aErr || uErr;
      const aliasById = new Map((aliases || []).map((a: { user_id: string; login_name: string }) => [a.user_id, a.login_name]));
      const usersById = new Map((users?.users || []).map((u: { id: string; email?: string }) => [u.id, u]));
      return json({ accounts: (profiles || []).map((p: { id: string; display_name: string; role: string }) => ({ id: p.id, display_name: p.display_name, role: p.role, login_name: aliasById.get(p.id) || '', mapped: aliasById.has(p.id), active: Boolean(usersById.get(p.id)) })) });
    }
    if (action === 'assign' || action === 'rename') {
      const id = String(payload.user_id || '');
      const loginName = String(payload.login_name || '').trim().toLowerCase();
      if (!id || !validLogin(loginName)) return fail('invalid_login_name');
      const { profile } = await findProfile(id);
      const { error } = await admin.from('auth_login_aliases').upsert({ user_id: id, login_name: loginName, created_by: callerId }, { onConflict: 'user_id' });
      if (error) throw error;
      return json({ account: { id, display_name: profile.display_name, role: profile.role, login_name: loginName, mapped: true } });
    }
    if (action === 'set_role') return json({ account: await setRole(String(payload.user_id || ''), String(payload.role || '')) });
    if (action === 'create') {
      const displayName = String(payload.display_name || '').trim();
      const loginName = String(payload.login_name || '').trim().toLowerCase();
      const role = String(payload.role || '');
      const password = String(payload.password || '');
      if (!displayName || !validLogin(loginName) || !roles.has(role) || password.length < 10) return fail('invalid_account_fields');
      const email = `${loginName}@accounts.invalid`;
      const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, app_metadata: { role }, user_metadata: { display_name: displayName } });
      if (error || !data.user) throw error || new Error('account_create_failed');
      const { error: profileError } = await admin.from('profiles').upsert({ id: data.user.id, display_name: displayName, role });
      if (profileError) { await admin.auth.admin.deleteUser(data.user.id); throw profileError; }
      const { error: aliasError } = await admin.from('auth_login_aliases').insert({ user_id: data.user.id, login_name: loginName, created_by: callerId });
      if (aliasError) { await admin.auth.admin.deleteUser(data.user.id); throw aliasError; }
      return json({ account: { id: data.user.id, display_name: displayName, role, login_name: loginName, mapped: true } }, 201);
    }
    if (action === 'reset_password') {
      const targets = Array.isArray(payload.user_ids) ? [...new Set(payload.user_ids.map(String))] : [];
      const password = String(payload.password || '');
      if (!targets.length || targets.length > 100 || password.length < 10) return fail('invalid_reset_request');
      const results = [];
      for (const id of targets) {
        const { auth, profile } = await findProfile(id);
        const { error } = await admin.auth.admin.updateUserById(id, { password });
        if (error) throw error;
        results.push({ id, display_name: profile.display_name, role: profile.role, login_name: null });
      }
      const { data: aliases } = await admin.from('auth_login_aliases').select('user_id,login_name').in('user_id', targets);
      const byId = new Map((aliases || []).map((a: { user_id: string; login_name: string }) => [a.user_id, a.login_name]));
      return json({ updated: results.map(row => ({ ...row, login_name: byId.get(row.id) || '' })) });
    }
    return fail('unknown_action');
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    if (['account_not_found', 'invalid_role', 'last_owner'].includes(message)) return json({ error: message }, 400);
    return json({ error: 'account_operation_failed' }, 400);
  }
});
