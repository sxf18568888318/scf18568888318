import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('./reno-cloud-owner.inc.js', import.meta.url), 'utf8');
const loader = source.slice(source.indexOf('  async function rcLoad('), source.indexOf('  async function rcLoadProfile('));

async function loadWithFailure(failedEndpoint) {
  const rc = { loading:false, loaded:false, error:'', customers:[], months:[] };
  const context = {
    rc, role:'owner', module:'whole', render:()=>{}, rcFail:error=>error.message,
    rcClient:()=>({ schema:()=>({ rpc:async()=>({data:[],error:null}) }) }),
    rcRead:async endpoint => {
      if (endpoint === failedEndpoint) throw Error('diagnostic payroll failure');
      return endpoint === 'reno_customers' ? [{id:'customer-kept'}] : [{endpoint}];
    },
  };
  vm.runInNewContext(loader, context);
  await context.rcLoad();
  return rc;
}

test('a financial endpoint failure preserves successfully loaded customer records and names the failed endpoint', async () => {
  const rc = await loadWithFailure('owner_monthly_net_profit');
  assert.equal(rc.customers[0]?.id, 'customer-kept');
  assert.match(rc.error, /owner_monthly_net_profit/);
  assert.match(rc.error, /diagnostic payroll failure/);
  assert.equal(rc.loading, false);
});

test('a complete cloud load includes financial data and finishes the loading state', async () => {
  const rc = await loadWithFailure(null);
  assert.equal(rc.customers[0]?.id, 'customer-kept');
  assert.equal(rc.months[0]?.endpoint, 'owner_monthly_net_profit');
  assert.equal(rc.loaded, true);
  assert.equal(rc.loading, false);
  assert.equal(rc.error, '');
});
