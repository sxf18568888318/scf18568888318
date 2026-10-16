import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const logic = fs.readFileSync(new URL('./cloud-draft.logic.js', import.meta.url), 'utf8');
const context = { window: {}, setTimeout, clearTimeout, Promise };
vm.runInNewContext(logic, context, { filename: 'cloud-draft.logic.js' });

test('renovation units map to the correct projection mode', () => {
  const mode = context.window.__YJQuotePricingMode;
  assert.equal(mode('投影'), '投影');
  assert.equal(mode('m²'), '平方');
  assert.equal(mode('延米'), '延米');
  assert.equal(mode('项'), '按单位');
});

test('owner and designer quote editors show usable dimension inputs and derived area', () => {
  for (const file of ['./reno-cloud-owner.inc.js', './reno-cloud-staff.inc.js']) {
    const source = fs.readFileSync(new URL(file, import.meta.url), 'utf8');
    assert.match(source, /__YJQuotePricingMode\(u\)/);
    assert.match(source, /qty\.readOnly=mode!=='按单位'/);
    assert.match(source, /row\.dataset\.pricingMode=mode/);
  }
  const css = fs.readFileSync(new URL('./acceptance-repair.css', import.meta.url), 'utf8');
  assert.match(css, /data-pricing-mode="投影"/);
  assert.match(css, /data-pricing-mode="平方"/);
  assert.match(css, /\[hidden\]\s*\{\s*display:none\s*!important/s);
});
