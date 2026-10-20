// Domain: Shared
// Type: logic
// Note: Pure logic used by workflow modules.
// Description: Workflow restoration logic helpers.

// Small deterministic helpers shared by restored cloud workflows and tests.
(function (root) {
  function cents(value) {
    const number = Number(value);
    if (!Number.isFinite(number) || number < 0) throw new Error('费用和折让必须是非负数');
    return Math.round(number * 100);
  }

  function distributeCents(total, weights) {
    if (!weights.length) return [];
    const sum = weights.reduce((acc, value) => acc + value, 0);
    if (sum <= 0) return weights.map((_, index) => index === 0 ? total : 0);
    const exact = weights.map(value => total * value / sum);
    const allocated = exact.map(Math.floor);
    let remaining = total - allocated.reduce((acc, value) => acc + value, 0);
    const byRemainder = exact.map((value, index) => ({ index, remainder: value - allocated[index] }))
      .sort((a, b) => b.remainder - a.remainder || a.index - b.index);
    for (let i = 0; i < remaining; i++) allocated[byRemainder[i].index] += 1;
    return allocated;
  }

  function allocateInvoice(lines, fee = 0, discount = 0) {
    if (!Array.isArray(lines) || !lines.length) throw new Error('至少需要一条单据明细');
    const populated = lines.map((line, index) => ({ line, index })).filter(({ line }) => {
      // Unit may be prefilled by the UI; an otherwise untouched row is still blank.
      const fields = [line.product, line.quantity, line.unitPrice, line.amount];
      return fields.some(value => String(value ?? '').trim() !== '');
    });
    if (!populated.length) throw new Error('至少需要一条有效单据明细');
    const normalized = populated.map(({ line, index }) => {
      const quantity = Number(line.quantity);
      const unitPrice = Number(line.unitPrice);
      const amount = Number(line.amount);
      if (!String(line.product || '').trim() || !String(line.unit || '').trim()) throw new Error(`第 ${index + 1} 行需要品名和单位`);
      if (!(quantity > 0) || !(unitPrice >= 0) || !(amount > 0) || ![quantity, unitPrice, amount].every(Number.isFinite)) throw new Error(`第 ${index + 1} 行需要正数量及有效单价、金额`);
      if (Math.abs(Math.round(quantity * unitPrice * 100) - Math.round(amount * 100)) > 5) throw new Error(`第 ${index + 1} 行数量×单价与金额不一致`);
      return { ...line, product: String(line.product).trim(), unit: String(line.unit).trim(), quantity, unitPrice, amount: Math.round(amount * 100) / 100 };
    });
    const weights = normalized.map(line => Math.round(line.amount * 100));
    const subtotal = weights.reduce((sum, value) => sum + value, 0);
    const feeCents = cents(fee);
    const discountCents = cents(discount);
    if (discountCents > subtotal) throw new Error('折让不能超过明细金额');
    const feeParts = distributeCents(feeCents, weights);
    const discountParts = distributeCents(discountCents, weights);
    return normalized.map((line, index) => ({
      ...line,
      postedAmount: (weights[index] + feeParts[index] - discountParts[index]) / 100,
    }));
  }

  function mergeInvoiceScanLines(existing, recognized) {
    const hasContent = line => [line.product, line.quantity, line.unitPrice, line.amount, line.remark]
      .some(value => String(value ?? '').trim() !== '');
    const current = (existing || []).filter(hasContent);
    return current.length ? [...current, ...(recognized || [])] : [...(recognized || [])];
  }

  function initialAttendanceRows(employees) {
    return (employees || []).filter(employee => employee.employment_status === '在职').map(employee => ({
      employee_id: employee.id,
      status: '出勤',
      hours: 8,
      piece_quantity: 0,
      overtime_hours: 0,
      allocations: [],
    }));
  }

  function purchaseStorageKind(kind) {
    return ({ '板材单': 'board', '五金单': 'hardware', '封边单': 'edging' })[kind] || 'documents';
  }

  function documentStorageFolder(kind) {
    return ({ '图纸': 'drawings', '板材单': 'board', '五金单': 'hardware', '封边单': 'edging',
      '合同': 'contracts', '变更单': 'changes', '其他资料': 'documents', '现场照片': 'site-photos',
      '采购单': 'purchase', '费用凭证': 'expense' })[kind] || 'documents';
  }

  function safeStorageSegment(value) {
    return String(value ?? '').normalize('NFKD').replace(/[^a-zA-Z0-9._-]/g, '_').replace(/^\.+|\.+$/g, '') || 'file';
  }

  function isFactoryCostAction(action) {
    return action === 'fc-cost-new';
  }

  root.ANJUWorkflowRestoration = { allocateInvoice, mergeInvoiceScanLines, initialAttendanceRows, purchaseStorageKind, documentStorageFolder, safeStorageSegment, isFactoryCostAction };
})(globalThis);
