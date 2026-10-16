/* Small shared debounce/flush helper for cloud-backed quotation drafts. */
window.__YJCloudDraftQueue = function createYJCloudDraftQueue({delay=900, save, onState=()=>{}}={}) {
  if (typeof save !== 'function') throw new TypeError('Cloud draft save callback is required');
  let timer = null;
  let pending = null;
  let sequence = 0;
  let dirty = false;
  let chain = Promise.resolve();

  function schedule(payload) {
    pending = payload;
    dirty = true;
    sequence += 1;
    if (timer) clearTimeout(timer);
    onState('pending');
    timer = setTimeout(() => { flush().catch(() => {}); }, delay);
  }

  function flush() {
    if (timer) { clearTimeout(timer); timer = null; }
    if (pending === null) return chain;
    const payload = pending;
    pending = null;
    const version = sequence;
    onState('saving');
    const attempt = chain.catch(() => {}).then(() => save(payload));
    chain = attempt.then(result => {
      if (version === sequence) {
        dirty = false;
        onState('saved', result);
      }
      return result;
    }, error => {
      if (version === sequence) {
        if (pending === null) pending = payload;
        dirty = true;
        onState('failed', error);
      }
      throw error;
    });
    return chain;
  }

  async function wait() {
    if (timer) { clearTimeout(timer); timer = null; }
    if (pending !== null) await flush();
    else await chain;
    return !dirty;
  }

  function cancel() {
    if (timer) { clearTimeout(timer); timer = null; }
  }

  return { schedule, flush, wait, cancel, get dirty() { return dirty; } };
};
window.__YJQuoteQuantity = function calculateQuoteQuantity(mode, quantity, widthMm, heightMm, lengthM) {
  const q = Number(quantity || 0), width = Number(widthMm || 0), height = Number(heightMm || 0);
  if (mode === '投影' || mode === '平方') return Math.round(width * height / 1000000 * 10000) / 10000;
  if (mode === '延米') return Math.round((Number(lengthM || 0) || width / 1000) * 10000) / 10000;
  return q;
};
window.__YJQuotePricingMode = function quotePricingMode(unit) {
  const value = String(unit || '项');
  if (value === '投影') return '投影';
  if (['平方','m²','㎡'].includes(value)) return '平方';
  if (['延米','m'].includes(value)) return '延米';
  return '按单位';
};
window.__YJCustomDraftPayload = function serializeCustomDraft(q) {
  const copy = value => value == null ? value : JSON.parse(JSON.stringify(value));
  const material = value => {
    const source = value || {};
    return Object.fromEntries(['brand','substrate','thickness','color','door','finish','grade','model','spec'].filter(key => source[key] != null).map(key => [key, String(source[key])]));
  };
  return {
    type: '全屋定制', customerId: String(q.customerId || ''), customer: String(q.customer || ''),
    address: String(q.address || ''), contact: String(q.contact || ''), phone: String(q.phone || ''),
    owner: String(q.owner || ''), date: String(q.date || ''), validity: String(q.validity || ''),
    requirements: String(q.requirements || ''), exclusions: String(q.exclusions || ''),
    customerType: String(q.customerType || ''), channel: String(q.channel || ''),
    payments: String(q.payments || ''), channelTerms: String(q.channelTerms || ''),
    discount: Number(q.discount || 0), deliveryFee: Number(q.deliveryFee || 0), installFee: Number(q.installFee || 0),
    projectedPrice: Number(q.projectedPrice || 0), linearPrice: Number(q.linearPrice || 0),
    factoryOrderNo: String(q.factoryOrderNo || ''), measurementDate: String(q.measurementDate || ''),
    deliveryDate: String(q.deliveryDate || ''), clientProjectedArea: Number(q.clientProjectedArea || 0),
    clientDoorArea: Number(q.clientDoorArea || 0), orderNote: String(q.orderNote || ''),
    rooms: Array.isArray(q.rooms) ? q.rooms.map(String) : [], activeRoom: String(q.activeRoom || ''),
    baseMaterial: material(q.baseMaterial), doorMaterial: material(q.doorMaterial),
    rows: Array.isArray(q.rows) ? q.rows.map(row => ({
      name: String(row.name || ''), category: String(row.category || ''), mode: String(row.mode || ''),
      unit: String(row.unit || ''), qty: Number(row.qty || 0), quantity: Number(row.quantity || row.qty || 0),
      width: Number(row.width || 0), height: Number(row.height || 0), depth: Number(row.depth || 0), deduct: Number(row.deduct || 0),
      price: Number(row.price || 0), amount: Number(row.amount || 0), room: String(row.room || ''),
      spec: String(row.spec || ''), remark: String(row.remark || ''), note: String(row.note || ''),
      included: Boolean(row.included), charge: String(row.charge || ''), includedIn: String(row.includedIn || ''),
      expandedArea: Number(row.expandedArea || 0), directArea: Number(row.directArea || 0), measureVersion: Number(row.measureVersion || 0), measureSource: String(row.measureSource || ''), material: material(row.material),
      standalonePrice: Number(row.standalonePrice || 0), upgradePrice: Number(row.upgradePrice || 0)
    })) : [],
    documents: Array.isArray(q.documents) ? copy(q.documents) : [],
    subtotal: Number(q.subtotal || 0), amount: Number(q.amount || 0), savedAt: new Date().toISOString()
  };
};
