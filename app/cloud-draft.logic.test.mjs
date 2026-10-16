import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

const source = fs.readFileSync(new URL('./cloud-draft.logic.js', import.meta.url), 'utf8');
const context = { window: {}, setTimeout, clearTimeout, Promise };
vm.runInNewContext(source, context, { filename: 'cloud-draft.logic.js' });

test('cloud draft queue flushes the newest snapshot before navigation', async () => {
  const saved = [];
  const states = [];
  const queue = context.window.__YJCloudDraftQueue({ delay: 50, save: async payload => saved.push(payload), onState: state => states.push(state) });
  queue.schedule({ line: 'first' });
  queue.schedule({ line: 'latest' });
  await queue.flush();
  assert.deepEqual(saved, [{ line: 'latest' }]);
  assert.ok(states.includes('saved'));
});

test('cloud draft queue keeps failed snapshots retryable and reports failure', async () => {
  let attempts = 0;
  const states = [];
  const queue = context.window.__YJCloudDraftQueue({ delay: 50, save: async () => { attempts++; if (attempts === 1) throw Error('offline'); }, onState: state => states.push(state) });
  queue.schedule({ id: 'draft-1' });
  await assert.rejects(queue.flush(), /offline/);
  assert.ok(states.includes('failed'));
  await queue.flush();
  assert.equal(attempts, 2);
  assert.ok(states.includes('saved'));
});
test('reno quote quantity uses dimensions for projection, square, and linear modes', () => {
  const calc = context.window.__YJQuoteQuantity;
  assert.equal(calc('投影', 1, 2000, 2400), 4.8);
  assert.equal(calc('平方', 1, 2500, 3200), 8);
  assert.equal(calc('延米', 1, 3200, 0), 3.2);
  assert.equal(calc('按单位', 2.5, 2000, 2400), 2.5);
});

test('custom quote draft serialization keeps all line fields needed to resume without local storage', () => {
  const payload = context.window.__YJCustomDraftPayload({
    id: 'local-id', customerId: 'customer-1', customer: '样板客户', rooms: ['主卧'], activeRoom: '主卧',
    rows: [{ name: '衣柜', category: '柜体定制', unit: '㎡', qty: 2, quantity: 4.2, width: 2000, height: 2100, depth: 600, price: 1280, amount: 5376, room: '主卧', spec: '18mm', note: '备注换行', material: { brand: '示例', purchaseReference: 420 }, purchaseReference: 330 }],
    documents: [{ id: 'file-1', name: '图纸.pdf' }], discount: 100, amount: 5276
  });
  assert.equal(payload.customerId, 'customer-1');
  assert.equal(payload.rows[0].quantity, 4.2);
  assert.equal(payload.rows[0].qty, 2);
  assert.equal(payload.rows[0].width, 2000);
  assert.equal(payload.rows[0].height, 2100);
  assert.equal(payload.rows[0].note, '备注换行');
  assert.equal(payload.rows[0].material.brand, '示例');
  assert.equal(Object.hasOwn(payload.rows[0], 'purchaseReference'), false);
  assert.equal(Object.hasOwn(payload.rows[0].material, 'purchaseReference'), false);
  assert.equal(payload.documents[0].name, '图纸.pdf');
  assert.equal(payload.amount, 5276);
  assert.equal(Object.hasOwn(payload, 'id'), false);
});

test('custom quote editor sends drafts to the scoped cloud API and offers cloud recovery', () => {
  const source = readFileSync(new URL('./custom-cloud-drafts.inc.js', import.meta.url), 'utf8');
  assert.match(source, /schema\('api'\)\.rpc\('custom_save_quote_draft'/);
  assert.match(source, /custom_quote_draft_details/);
  assert.match(source, /data-action="ccd-open"/);
  assert.match(source, /云端草稿已保存/);
  assert.doesNotMatch(source, /localStorage\.setItem\([^)]*custom.*draft/i);
});

test('custom quote autosaves reuse the cloud ID when a second edit arrives during the first save', () => {
  const source = readFileSync(new URL('./custom-cloud-drafts.inc.js', import.meta.url), 'utf8');
  assert.match(source, /p_quote_id:snapshot\.quoteId\|\|quoteDraftId\|\|null/);
});

test('custom quote navigation waits for the cloud save before replacing the editor', () => {
  const source = readFileSync(new URL('./custom-cloud-drafts.inc.js', import.meta.url), 'utf8');
  assert.match(source, /async function ccdFlushBeforeNavigation\(/);
  assert.match(source, /const ccdLeavingActions=new Set\(/);
});

test('custom quote backend migration stores draft payloads without booking revenue and gates writes', () => {
  const migration = readFileSync(new URL('../supabase/migrations/20261014133000_custom_cloud_quote_drafts.sql', import.meta.url), 'utf8');
  assert.match(migration, /perform custom_private\.require_roles\(array\['owner','designer'\]\)/);
  assert.match(migration, /business_line='custom'.*status='draft'/s);
  assert.match(migration, /set custom_draft_payload=p_payload/);
  assert.match(migration, /amount=0/);
  assert.match(migration, /p_payload->>'customerId' is distinct from p_customer_id::text/);
});

test('custom designer progress reader is scoped to allowed customers and exposes no financial columns', () => {
  const migration = readFileSync(new URL('../supabase/migrations/20261014134500_custom_factory_progress_designer.sql', import.meta.url), 'utf8');
  const source = readFileSync(new URL('./custom-cloud-drafts.inc.js', import.meta.url), 'utf8');
  assert.match(migration, /custom_private\.customer_allowed\(f\.customer_id\)/);
  assert.match(migration, /custom_quote_id/);
  assert.doesNotMatch(migration, /order_amount|board_cost|gross_profit|total_cost|margin/i);
  assert.match(source, /ccdRead\('custom_factory_progress'\)/);
  assert.match(source, /当前工厂进度/);
});

test('custom cloud quote list includes every cloud quote state, not only workbench drafts', () => {
  const source = readFileSync(new URL('./custom-cloud-drafts.inc.js', import.meta.url), 'utf8');
  assert.match(source, /cqList=function\(\).*?ccd\.quotes\.map/s);
  assert.match(source, /hasDraft\?`<button[^`]*继续编辑/s);
});

test('custom customer workspace uses cloud quote, production, and receivable views', () => {
  const source = readFileSync(new URL('./custom-cloud-drafts.inc.js', import.meta.url), 'utf8');
  assert.match(source, /ccdRead\('my_custom_order_receivables'\)/);
  assert.match(source, /function ccdCustomerPage\(/);
  assert.match(source, /data-action="ccd-customer-open"/);
  assert.match(source, /data-action="ccd-new-quote-customer"/);
});
