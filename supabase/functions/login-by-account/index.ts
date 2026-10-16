const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  try {
    const { account, password } = await req.json();
    const loginName = String(account || '').trim().toLowerCase();
    if (!/^yj18568888318-[0-9]{2,}$/.test(loginName) || typeof password !== 'string' || !password) return json({ error: 'invalid_credentials' }, 401);
    const url = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anonKey = req.headers.get('apikey') || '';
    const lookup = await fetch(`${url}/rest/v1/auth_login_aliases?select=user_id&login_name=eq.${encodeURIComponent(loginName)}`, { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
    const rows = await lookup.json();
    if (!lookup.ok || !rows?.[0]?.user_id) return json({ error: 'invalid_credentials' }, 401);
    const userResponse = await fetch(`${url}/auth/v1/admin/users/${rows[0].user_id}`, { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
    const user = await userResponse.json();
    if (!userResponse.ok || !user.email) return json({ error: 'invalid_credentials' }, 401);
    const authResponse = await fetch(`${url}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: anonKey, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: user.email, password }) });
    const session = await authResponse.json();
    if (!authResponse.ok) return json({ error: 'invalid_credentials' }, 401);
    return json({ access_token: session.access_token, refresh_token: session.refresh_token, token_type: session.token_type, expires_in: session.expires_in, expires_at: session.expires_at, user: session.user });
  } catch { return json({ error: 'invalid_credentials' }, 401); }
});
