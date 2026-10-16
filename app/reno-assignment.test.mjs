import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('renovation assignment RPC is role-gated and validates real account roles', () => {
  const migration = fs.readFileSync(new URL('../supabase/migrations/20261016190000_reno_customer_staff_assignment.sql', import.meta.url), 'utf8');
  assert.match(migration, /v_role not in \('owner','designer'\)/);
  assert.match(migration, /reno_customer_allowed\(p_customer_id\)/);
  assert.match(migration, /raw_app_meta_data->>'role'='foreman'/);
  assert.match(migration, /raw_app_meta_data->>'role' in \('sales','designer'\)/);
  assert.match(migration, /update public\.reno_order_stages/);
  assert.doesNotMatch(migration, /delete from public\.(customers|reno_orders|reno_order_stages)/i);
});
