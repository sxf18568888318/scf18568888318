import assert from 'node:assert/strict';
import './workflow-restoration.logic.js';

const { allocateInvoice, mergeInvoiceScanLines, initialAttendanceRows, purchaseStorageKind, documentStorageFolder, safeStorageSegment, isFactoryCostAction } = globalThis.ANJUWorkflowRestoration;

assert.deepEqual(
  allocateInvoice([
    { product: '板材', unit: '张', quantity: 2, unitPrice: 100, amount: 200, category: '板材' },
    { product: '封边', unit: '米', quantity: 10, unitPrice: 5, amount: 50, category: '封边' },
  ], 10, 5),
  [
    { product: '板材', unit: '张', quantity: 2, unitPrice: 100, amount: 200, category: '板材', postedAmount: 204 },
    { product: '封边', unit: '米', quantity: 10, unitPrice: 5, amount: 50, category: '封边', postedAmount: 51 },
  ],
  'fees and discounts should be allocated proportionally and preserve the invoice total',
);

assert.throws(
  () => allocateInvoice([{ product: '错误行', unit: '张', quantity: 2, unitPrice: 100, amount: 190 }], 0, 0),
  /数量×单价/,
  'invoice review should reject inconsistent line totals',
);

assert.deepEqual(
  allocateInvoice([
    { product: '', unit: '张', quantity: '', unitPrice: '', amount: '' },
    { product: '板材', unit: '张', quantity: 2, unitPrice: 100, amount: 200 },
    { product: '', unit: '', quantity: '', unitPrice: '', amount: '' },
  ], 0, 0).map(({ product, postedAmount }) => ({ product, postedAmount })),
  [{ product: '板材', postedAmount: 200 }],
  'fully blank invoice rows should be ignored before validation',
);
assert.throws(
  () => allocateInvoice([{ product: '', unit: '', quantity: 2, unitPrice: '', amount: '' }], 0, 0),
  /第 1 行需要品名和单位/,
  'partially completed invoice rows should still be rejected',
);
assert.equal(purchaseStorageKind('板材单'), 'board');
assert.equal(purchaseStorageKind('五金单'), 'hardware');
assert.equal(purchaseStorageKind('封边单'), 'edging');
assert.equal(documentStorageFolder('现场照片'), 'site-photos');
assert.match(safeStorageSegment('五金单/采购 单.png'), /^[a-zA-Z0-9._-]+$/);
assert.equal(isFactoryCostAction('fc-cost-new'), true);
assert.equal(isFactoryCostAction('fc-process'), false, 'process forms must never fall through to cost entry');
assert.deepEqual(mergeInvoiceScanLines([{ product: '', unit: '张', quantity: '', unitPrice: '', amount: '' }], [{ product: '柜体板', unit: '张', quantity: 2 }]), [{ product: '柜体板', unit: '张', quantity: 2 }]);
assert.deepEqual(mergeInvoiceScanLines([{ product: '人工核对过的板材', unit: '张', quantity: 2, unitPrice: 90, amount: 180 }], [{ product: '新识别五金', unit: '套', quantity: 1 }]), [{ product: '人工核对过的板材', unit: '张', quantity: 2, unitPrice: 90, amount: 180 }, { product: '新识别五金', unit: '套', quantity: 1 }]);

assert.deepEqual(
  initialAttendanceRows([{ id: 'e1', employee_name: '甲', employment_status: '在职' }, { id: 'e2', employee_name: '乙', employment_status: '离职' }]),
  [{ employee_id: 'e1', status: '出勤', hours: 8, piece_quantity: 0, overtime_hours: 0, allocations: [] }],
  'attendance batch should default every active employee to present and omit inactive staff',
);
