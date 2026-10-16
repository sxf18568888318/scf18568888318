(() => {
  'use strict';
  const units = Object.freeze({
    hardwareCatalog: Object.freeze(['个', '副', '套', '米', '张']),
    hardwareBom: Object.freeze(['个', '副', '套', '米', '张']),
    boardBom: Object.freeze(['张', '㎡', '延米', '个', '米'])
  });
  const number = value => Number.isFinite(Number(value)) ? Number(value) : 0;
  function sheetAreaM2(size) {
    const parts = String(size || '').match(/[\d.]+/g);
    if (!parts || parts.length < 2) return null;
    const area = Number(parts[0]) * Number(parts[1]) / 1_000_000;
    return area > 0 ? Math.round(area * 1e6) / 1e6 : null;
  }
  function procurementSheets({ unit, quantity, standardSize, utilizationRate = 1, linearWidthMm = null }) {
    const qty = number(quantity), utilization = number(utilizationRate);
    if (qty < 0 || utilization <= 0 || utilization > 1) return null;
    if (unit === '张') return Math.ceil(qty);
    if (!['㎡', '延米'].includes(unit)) return null;
    const sheetArea = sheetAreaM2(standardSize);
    if (!sheetArea) return null;
    let demandArea = qty;
    if (unit === '延米') {
      const width = number(linearWidthMm);
      if (width <= 0) return null;
      demandArea = qty * width / 1000;
    }
    return Math.ceil(demandArea / (sheetArea * utilization));
  }
  function hardwareSalesAmount({ quantity, salesUnitPrice, includedInBase }) {
    return includedInBase ? 0 : Math.round(number(quantity) * number(salesUnitPrice) * 100) / 100;
  }
  function edgeSalesAmount({ chargeMode, lengthM, pricePerMeter }) {
    return chargeMode === 'separate' ? Math.round(number(lengthM) * number(pricePerMeter) * 100) / 100 : 0;
  }
  function normalizePartUse(partUse, note = '') {
    if (partUse === '层板(加厚)') return { partUse: '层板', note: `样板部位：层板(加厚)${note ? `；${note}` : ''}` };
    return { partUse, note: note || '' };
  }
  function catalogPayload(role, kind, values) {
    const payload = { ...values };
    if (role !== 'owner') delete payload.reference_purchase_price;
    if (payload.default_sales_price === '' || payload.default_sales_price == null) payload.default_sales_price = 0;
    if (kind === 'hardware' && !units.hardwareCatalog.includes(payload.unit)) throw new Error('五金档案单位无效');
    return payload;
  }
  const api = Object.freeze({ units, sheetAreaM2, procurementSheets, hardwareSalesAmount, edgeSalesAmount, normalizePartUse, catalogPayload });
  const root = typeof window !== 'undefined' ? window : globalThis;
  root.anjuCustomBomLogic = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
