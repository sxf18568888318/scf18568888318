import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('./role-gates.inc.js', import.meta.url), 'utf8');
const procurement = readFileSync(new URL('./custom-procurement.inc.js', import.meta.url), 'utf8');

test('role gate source protects foreman whole finance and quote routes and removes sensitive dashboard cards', () => {
  assert.match(source, /role === 'foreman'.*moduleId === 'whole'.*quotes/s);
  assert.match(source, /pageId === 'nw-finance'/);
  assert.match(source, /\['nw-finance', 'rx-finance'\]/);
  assert.match(source, /pageId === 'expenses'/);
});

test('factory manager cannot access custom finance or legacy expenses through navigation or direct route', () => {
  assert.match(source, /pageId === 'custom-finance'.*role !== 'owner'/);
  assert.match(source, /pageId === 'expenses'.*role !== 'owner'/);
  assert.match(source, /const factoryBlocked = role === 'factory'/);
});

test('custom cloud pages expose loading and error states and auto-load on direct entry', () => {
  assert.match(procurement, /加载中…/);
  assert.match(procurement, /读取定制财务失败/);
  assert.match(source, /cpLoadFinance\(\)/);
  assert.match(source, /cpLoad\(\)/);
});

test('plan records database RLS requirement for future renovation finance integration', () => {
  const plan = readFileSync(new URL('../docs/superpowers/plans/2026-10-11-step7-custom-finance.md', import.meta.url), 'utf8');
  assert.match(plan, /renovation finance.*RLS/i);
});
