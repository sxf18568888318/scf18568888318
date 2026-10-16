import test from 'node:test';
import assert from 'node:assert/strict';
import { isOwnerCaller } from '../supabase/functions/account-admin/authz.mjs';

test('account admin requires an authenticated identity and the current owner profile role', async () => {
  assert.equal(await isOwnerCaller('owner-id', async () => 'owner'), true);
  assert.equal(await isOwnerCaller('staff-id', async () => 'designer'), false);
  assert.equal(await isOwnerCaller(null, async () => 'owner'), false);
});

test('account admin fails closed when the role lookup fails', async () => {
  assert.equal(await isOwnerCaller('owner-id', async () => { throw new Error('db unavailable'); }), false);
});
