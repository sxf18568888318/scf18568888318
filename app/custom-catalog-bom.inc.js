// Domain: Custom Cabinetry
// Type: include
// Note: Concatenated into framework-preview.js
// Description: Custom catalog BOM user interface.

  // Secure catalog + multi-line custom quotation pages. This include is
  // intentionally isolated from the renovation quotation workflow.
  const customBomLogic = window.anjuCustomBomLogic;
  pages.custom.push(['custom-catalog', '板材与五金档案', '▤'], ['custom-bom', 'BOM 报价与用量', '▧']);
  rolePageAllow.sales.custom.add('custom-catalog');
  rolePageAllow.sales.custom.add('custom-bom');
  const canAccessPageBeforeCustomBom = canAccessPage;
  canAccessPage = function (moduleId, pageId) {
    if (moduleId === 'custom' && ['custom-catalog', 'custom-bom'].includes(pageId)) return role === 'owner' || role === 'sales';
    return canAccessPageBeforeCustomBom(moduleId, pageId);
  };
  let cbKind = 'board', cbCatalog = { board: [], hardware: [] }, cbPrices = [], cbEditing = null, cbImportSummary = null;
  let cbCustomers = [], cbCustomersLoaded = false, cbCustomersLoading = false;
  let cbFactoryManagers = [], cbQuoteId = '', cbQuoteTitle = '', cbQuoteStatus = 'draft', cbOrderId = '', cbOrderRows = [];
  let cbBoardItems = [], cbHardwareItems = [], cbBusy = false;
  const cbClient = () => window.__ANJU_AUTH__?.client || null;
  const cbDemoUrl = 'custom-catalog-demo.json';
  const cbEsc = value => esc(value);
  const cbFail = error => error?.message || error?.details || error?.hint || String(error || '请求失败');
  const cbNumber = value => value === '' || value == null ? 0 : Number(value);
  const cbOwner = () => role === 'owner';
  const cbRoleName = () => cbOwner() ? 'owner' : 'sales';
  const cbPriceMap = () => new Map(cbPrices.map(row => [row.catalog_id, row]));

  function cbFormField(name, label, value, options = {}) {
    const attrs = `name="${name}" ${options.required ? 'required' : ''} ${options.step ? `step="${options.step}"` : ''} ${options.min != null ? `min="${options.min}"` : ''} ${options.max != null ? `max="${options.max}"` : ''}`;
    if (options.choices) return `<label>${label}<select class="field" ${attrs}>${options.choices.map(choice => `<option value="${cbEsc(choice)}" ${String(value ?? '') === String(choice) ? 'selected' : ''}>${cbEsc(choice || '请选择')}</option>`).join('')}</select></label>`;
    return `<label>${label}<input class="field" ${attrs} type="${options.type || 'text'}" value="${cbEsc(value ?? '')}" placeholder="${cbEsc(options.placeholder || '')}"></label>`;
  }
  function cbCatalogForm(kind, record = {}) {
    const board = kind === 'board';
    const fields = board ? [
      cbFormField('material_name', '板材名称', record.material_name, { required: true }),
      cbFormField('category_use', '品类用途', record.category_use, { choices: ['', '柜体板', '柜门', '背板', '层板', '见光板', '其他'] }),
      cbFormField('brand', '品牌', record.brand),
      cbFormField('substrate', '基材', record.substrate, { choices: ['', '多层板', '颗粒板', '密度板', '生态板', '其他'] }),
      cbFormField('thickness_mm', '厚度（mm）', record.thickness_mm, { type: 'number', min: 0, step: '0.1' }),
      cbFormField('color_name', '花色名称', record.color_name),
      cbFormField('color_code', '花色编号 / 色号', record.color_code),
      cbFormField('finish_process', '饰面工艺', record.finish_process),
      cbFormField('eco_grade', '环保等级', record.eco_grade),
      cbFormField('edge_process', '封边工艺', record.edge_process, { choices: ['', 'EVA', 'PUR', '激光', '无'] }),
      cbFormField('standard_size', '标准规格（mm）', record.standard_size, { placeholder: '例如 1220×2440' }),
      cbFormField('pricing_method', '计价方式', record.pricing_method, { choices: ['', '按张', '按㎡', '按延米', '按件'] }),
      cbFormField('default_supplier', '默认供应商', record.default_supplier),
      cbFormField('status', '状态', record.status || '在用', { choices: ['在用', '备选', '停用'] }),
      cbFormField('note', '备注', record.note)
    ] : [
      cbFormField('hardware_name', '五金名称', record.hardware_name, { required: true }),
      cbFormField('major_category', '大类', record.major_category, { choices: ['', '铰链', '滑轨', '功能五金', '拉手', '连接件', '灯带电气', '其他'] }),
      cbFormField('spec', '细分规格', record.spec),
      cbFormField('brand', '品牌', record.brand),
      cbFormField('model', '型号', record.model),
      cbFormField('soft_close', '是否缓冲 / 阻尼', record.soft_close ? '是' : '否', { choices: ['是', '否'] }),
      cbFormField('unit', '档案单位', record.unit || '个', { choices: customBomLogic.units.hardwareCatalog }),
      cbFormField('default_supplier', '默认供应商', record.default_supplier),
      cbFormField('status', '状态', record.status || '在用', { choices: ['在用', '备选', '停用'] }),
      cbFormField('note', '备注', record.note)
    ];
    const prices = `<div class="cb-price-fields">${cbOwner() ? cbFormField('reference_purchase_price', '采购参考价（仅老板）', record.reference_purchase_price ?? 0, { type: 'number', min: 0, step: '0.01' }) : ''}${cbFormField('default_sales_price', '默认销售单价', record.default_sales_price ?? 0, { type: 'number', min: 0, step: '0.01' })}</div>`;
    return `<form id="cbCatalogForm" data-kind="${kind}" data-id="${cbEsc(record.id || '')}"><div class="cb-form-grid">${fields.join('')}${prices}</div><div class="cb-form-actions"><button type="button" class="btn" data-action="cb-cancel-edit">取消</button><button class="btn primary" ${cbBusy ? 'disabled' : ''}>${record.id ? '保存档案' : '新增档案'}</button></div></form>`;
  }
  function cbCatalogPage() {
    const rows = cbCatalog[cbKind] || [], prices = cbPriceMap();
    const name = cbKind === 'board' ? '板材' : '五金';
    const shown = rows.map(item => {
      const ownerPrice = prices.get(item.id);
      const specs = cbKind === 'board'
        ? [item.brand, item.substrate, `${item.thickness_mm || '—'}mm`, item.color_name, item.finish_process, item.standard_size].filter(Boolean).join(' · ')
        : [item.major_category, item.spec, item.brand, item.model, item.soft_close ? '缓冲' : '无缓冲'].filter(Boolean).join(' · ');
      const sales = Number(item.default_sales_price || 0);
      const procurement = cbOwner() ? `<td>${money(ownerPrice?.reference_purchase_price ?? 0)}</td>` : '';
      return `<tr><td><b>${cbEsc(cbKind === 'board' ? item.material_name : item.hardware_name)}</b><small class="cb-subline">${cbEsc(specs || '规格待补')}</small></td><td>${cbEsc(cbKind === 'board' ? item.category_use : item.major_category)}</td><td>${cbEsc(item.unit || item.pricing_method || '—')}</td><td>${money(sales)}</td>${procurement}<td><span class="tag ${item.status === '在用' ? 'green' : 'amber'}">${cbEsc(item.status)}</span></td><td><button class="btn small" data-action="cb-edit-catalog" data-kind="${cbKind}" data-id="${cbEsc(item.id)}">编辑</button></td></tr>`;
    }).join('');
    const edit = cbEditing ? `<section class="panel cb-edit-panel"><header><div><h3>${cbEditing.id ? '编辑' : '新增'}${name}档案</h3><p>${cbOwner() ? '老板可分别维护采购参考价和销售单价。' : '设计师只维护销售单价，不读取或提交采购参考价。'}</p></div></header>${cbCatalogForm(cbKind, cbEditing)}</section>` : '';
    const firstName = cbKind === 'board' ? '鲁丽多层18暖白' : '缓冲铰链-全盖';
    const firstRecord = rows.find(item => (cbKind === 'board' ? item.material_name : item.hardware_name) === firstName);
    const ownerFields = cbOwner() ? prices.get(firstRecord?.id) : null;
    const fullFields = firstRecord ? { ...firstRecord, ...(ownerFields ? { reference_purchase_price: ownerFields.reference_purchase_price } : {}) } : null;
    const fullRecord = fullFields ? `<details class="panel cb-record-review"><summary>首条样板完整字段 · ${cbEsc(firstName)}</summary><pre>${cbEsc(JSON.stringify(fullFields, null, 2))}</pre></details>` : '';
    const importResult = cbImportSummary && cbOwner() ? `<div class="cb-import-result"><b>本次样板导入结果</b><span>板材新增 ${cbImportSummary.board} 条；五金新增 ${cbImportSummary.hardware} 条。</span><small>同名跳过：板材 ${cbImportSummary.skippedBoard} 条、五金 ${cbImportSummary.skippedHardware} 条。</small></div>` : '';
    return `${head('CUSTOM CATALOG · 真实档案', '板材与五金档案', '样板档案按字段导入；采购参考价与销售价分开，设计师页面不包含采购价字段。', `<button class="btn" data-action="cb-import-demo" ${cbBusy || !cbOwner() ? 'disabled' : ''}>导入样板档案</button><button class="btn primary" data-action="cb-new-catalog">＋ 新增${name}</button>`)}
      <div class="cb-steps"><span class="cb-step done">2 · 样板档案</span><span class="cb-step active">3 · 价格维护</span><span class="cb-step">4 · BOM 报价</span></div>
      <div class="cb-tabs"><button class="${cbKind === 'board' ? 'active' : ''}" data-action="cb-kind" data-kind="board">板材档案 <b>${cbCatalog.board.length}</b></button><button class="${cbKind === 'hardware' ? 'active' : ''}" data-action="cb-kind" data-kind="hardware">五金档案 <b>${cbCatalog.hardware.length}</b></button></div>
      ${importResult}${edit}${panel(`${name}档案`, cbOwner() ? '采购参考价入口：本页老板编辑表单中的“采购参考价（仅老板）”。' : '当前为设计师身份，仅展示和维护销售价格。', `<div class="table-wrap"><table class="cb-table"><thead><tr><th>名称 / 规格</th><th>类别</th><th>单位</th><th>销售单价</th>${cbOwner() ? '<th>采购参考价</th>' : ''}<th>状态</th><th></th></tr></thead><tbody>${shown || `<tr><td colspan="${cbOwner() ? 7 : 6}" class="cb-empty">正在读取安全档案视图…</td></tr>`}</tbody></table></div>`)}${fullRecord}
      <p class="cb-price-note">样板中的参考单价只写入采购参考价；未提供的销售单价初始化为 0，不会由采购价推算。</p>`;
  }

  async function cbLoadCatalog() {
    const client = cbClient();
    if (!client) return;
    const [boards, hardware] = await Promise.all([
      client.schema('api').from('custom_board_catalog_sales').select('*').order('material_name'),
      client.schema('api').from('custom_hardware_catalog_sales').select('*').order('hardware_name')
    ]);
    if (boards.error) throw boards.error;
    if (hardware.error) throw hardware.error;
    cbCatalog = { board: boards.data || [], hardware: hardware.data || [] };
    cbPrices = [];
    if (cbOwner()) {
      const result = await client.schema('api').from('owner_custom_catalog_prices').select('catalog_kind,catalog_id,reference_purchase_price,default_sales_price');
      if (result.error) throw result.error;
      cbPrices = result.data || [];
    }
  }
  async function cbSaveCatalog(form) {
    const kind = form.dataset.kind, data = Object.fromEntries(new FormData(form).entries());
    delete data.note_alt;
    if (kind === 'board') {
      data.thickness_mm = cbNumber(data.thickness_mm);
    } else data.soft_close = data.soft_close === '是';
    data.default_sales_price = cbNumber(data.default_sales_price);
    if (cbOwner()) data.reference_purchase_price = cbNumber(data.reference_purchase_price);
    const payload = customBomLogic.catalogPayload(cbRoleName(), kind, data);
    const { error } = await cbClient().schema('api').rpc('custom_save_catalog', { p_kind: kind, p_data: payload, p_id: form.dataset.id || null });
    if (error) throw error;
    cbEditing = null;
    await cbLoadCatalog();
    render();
    toast(`${kind === 'board' ? '板材' : '五金'}档案已保存`);
  }
  async function cbImportDemo() {
    if (!cbOwner()) throw new Error('仅老板可导入样板档案');
    cbBusy = true; render();
    try {
      const response = await fetch(cbDemoUrl, { cache: 'no-store' });
      if (!response.ok) throw new Error('未找到样板数据文件');
      const sample = await response.json();
      const existing = { board: new Set(cbCatalog.board.map(x => x.material_name)), hardware: new Set(cbCatalog.hardware.map(x => x.hardware_name)) };
      const result = { board: 0, hardware: 0, skippedBoard: 0, skippedHardware: 0 };
      for (const row of sample.boards) {
        if (existing.board.has(row.material_name)) { result.skippedBoard++; continue; }
        const payload = { ...row, reference_purchase_price: cbNumber(row.reference_purchase_price), default_sales_price: 0 };
        const saved = await cbClient().schema('api').rpc('custom_save_catalog', { p_kind: 'board', p_data: payload, p_id: null });
        if (saved.error) throw saved.error;
        result.board++;
      }
      for (const row of sample.hardware) {
        if (existing.hardware.has(row.hardware_name)) { result.skippedHardware++; continue; }
        const payload = { ...row, reference_purchase_price: cbNumber(row.reference_purchase_price), default_sales_price: 0 };
        const saved = await cbClient().schema('api').rpc('custom_save_catalog', { p_kind: 'hardware', p_data: payload, p_id: null });
        if (saved.error) throw saved.error;
        result.hardware++;
      }
      cbImportSummary = result;
      await cbLoadCatalog();
      cbBusy = false; render();
      toast(`导入完成：板材新增 ${result.board} 条，五金新增 ${result.hardware} 条；同名档案跳过 板材 ${result.skippedBoard} 条 / 五金 ${result.skippedHardware} 条`);
    } catch (error) { cbBusy = false; render(); toast(`导入失败：${cbFail(error)}`); }
  }
  async function cbLoadCustomers() {
    const client = cbClient();
    if (!client) return;
    const result = await client.from('customers').select('id,name,business_line,owner_id').eq('business_line', 'custom').limit(100);
    if (result.error) throw result.error;
    cbCustomers = result.data || [];
    cbCustomersLoaded = true;
  }
  async function cbLoadFactoryManagers() {
    if (!cbOwner()) return;
    const result = await cbClient().from('profiles').select('id,display_name').eq('role', 'factory_manager').order('display_name');
    if (result.error) throw result.error;
    cbFactoryManagers = result.data || [];
  }
  async function cbLoadQuote() {
    if (!cbQuoteId) { cbBoardItems = []; cbHardwareItems = []; cbQuoteStatus = 'draft'; cbOrderId = ''; cbOrderRows = []; return; }
    const client = cbClient();
    const [boards, hardware, quote] = await Promise.all([
      client.schema('api').from('custom_quote_board_items').select('*').eq('quote_id', cbQuoteId).order('item_no'),
      client.schema('api').from('custom_quote_hardware_items').select('*').eq('quote_id', cbQuoteId).order('item_no'),
      client.from('quotes').select('id,status').eq('id', cbQuoteId).maybeSingle()
    ]);
    if (boards.error) throw boards.error;
    if (hardware.error) throw hardware.error;
    if (quote.error) throw quote.error;
    cbBoardItems = boards.data || [];
    cbHardwareItems = hardware.data || [];
    cbQuoteStatus = quote.data?.status || 'draft';
  }
  async function cbLoadOrderBom() {
    if (!cbOwner()) { cbOrderRows = []; return; }
    const api = cbClient().schema('api').from('custom_order_bom_factory');
    if (!cbOrderId && cbQuoteStatus === 'ordered') {
      const sourceItem = cbBoardItems[0] || cbHardwareItems[0];
      if (sourceItem) {
        const linked = await api.select('factory_order_id').eq('source_item_id', sourceItem.id).limit(1);
        if (linked.error) throw linked.error;
        cbOrderId = linked.data?.[0]?.factory_order_id || '';
      }
    }
    if (!cbOrderId) { cbOrderRows = []; return; }
    const result = await api.select('item_kind,id,factory_order_id,source_item_id,unit,quantity,item_name').eq('factory_order_id', cbOrderId);
    if (result.error) throw result.error;
    cbOrderRows = result.data || [];
  }
  const cbBoardSelect = () => cbCatalog.board.filter(x => x.status !== '停用').map(x => `<option value="${cbEsc(x.id)}">${cbEsc(x.material_name)} · ${cbEsc(x.standard_size || '')} · 销售 ${money(x.default_sales_price)}</option>`).join('');
  const cbHardwareSelect = () => cbCatalog.hardware.filter(x => x.status !== '停用').map(x => `<option value="${cbEsc(x.id)}">${cbEsc(x.hardware_name)} · ${cbEsc(x.unit)} · 销售 ${money(x.default_sales_price)}</option>`).join('');
  function cbBoardRow(row) {
    const sheets = customBomLogic.procurementSheets({ unit: row.unit, quantity: row.quantity, standardSize: row.standard_size, utilizationRate: row.utilization_rate, linearWidthMm: row.linear_width_mm });
    const amount = Number(row.sales_amount || 0), edgeAmount = Number(row.edge_sales_amount || 0);
    const controls = cbQuoteStatus === 'draft' ? `<td><input class="field cb-inline" type="number" min="0" step="0.01" value="${cbEsc(row.sales_unit_price)}" data-row-price></td><td><input class="field cb-inline" type="number" min="0" step="0.1" value="${cbEsc(row.edge_length_m)}" data-row-edge-length></td><td><select class="field cb-inline" data-row-edge-mode><option value="included" ${row.edge_charge_mode === 'included' ? 'selected' : ''}>已含</option><option value="separate" ${row.edge_charge_mode === 'separate' ? 'selected' : ''}>单列</option></select></td><td><input class="field cb-inline" type="number" min="0" step="0.01" value="${cbEsc(row.edge_sales_price_per_meter_snapshot)}" data-row-edge-price ${row.edge_charge_mode === 'included' ? 'disabled' : ''}></td><td>${money(amount)}<small class="cb-subline">封边 ${money(edgeAmount)}</small></td><td>${sheets == null ? '—' : `${sheets} 张`}<small class="cb-subline">${row.unit === '米' ? '米不推算板张数' : '含利用率'}</small></td><td><button class="btn small" data-action="cb-save-board-row" data-id="${cbEsc(row.id)}">保存</button> <button class="btn small danger" data-action="cb-delete-board-row" data-id="${cbEsc(row.id)}">删</button></td>` : `<td>已锁定</td><td>${Number(row.edge_length_m || 0)} 米</td><td>${row.edge_charge_mode === 'separate' ? '单列' : '已含'}</td><td>${money(row.edge_sales_price_per_meter_snapshot)} / 米</td><td>${money(amount)}<small class="cb-subline">封边 ${money(edgeAmount)}</small></td><td>${sheets == null ? '—' : `${sheets} 张`}<small class="cb-subline">${row.unit === '米' ? '米不推算板张数' : '含利用率'}</small></td><td>已锁定</td>`;
    return `<tr><td>${cbEsc(row.space)}</td><td><b>${cbEsc(row.board_name)}</b><small class="cb-subline">${cbEsc(row.part_use)} · ${cbEsc(row.unit)} × ${row.quantity}</small></td><td>${money(row.sales_unit_price)} / ${cbEsc(row.unit)}</td>${controls}</tr>`;
  }
  function cbHardwareRow(row) {
    const controls = cbQuoteStatus === 'draft' ? `<td><input class="field cb-inline" type="number" min="0" step="0.01" value="${cbEsc(row.sales_unit_price)}" data-row-price></td><td><label class="cb-check"><input type="checkbox" data-row-included ${row.included_in_base ? 'checked' : ''}> 已含基础配套</label></td><td>${money(row.sales_amount)}${row.included_in_base ? '<small class="cb-subline">已含金额为 0</small>' : ''}</td><td><button class="btn small" data-action="cb-save-hardware-row" data-id="${cbEsc(row.id)}">保存</button> <button class="btn small danger" data-action="cb-delete-hardware-row" data-id="${cbEsc(row.id)}">删</button></td>` : `<td>${row.included_in_base ? '已含基础配套' : '单列'}</td><td>${money(row.sales_amount)}${row.included_in_base ? '<small class="cb-subline">已含金额为 0</small>' : ''}</td><td>已锁定</td>`;
    return `<tr><td>${cbEsc(row.use_location)}</td><td><b>${cbEsc(row.hardware_name)}</b><small class="cb-subline">${cbEsc(row.spec)} · ${cbEsc(row.unit)} × ${row.quantity}</small></td><td>${money(row.sales_unit_price)} / ${cbEsc(row.unit)}</td>${controls}</tr>`;
  }
  function cbBomPage() {
    const quoteExists = Boolean(cbQuoteId), quoteDraft = cbQuoteStatus === 'draft', boardTotal = cbBoardItems.reduce((sum, row) => sum + Number(row.sales_amount || 0) + Number(row.edge_sales_amount || 0), 0), hardwareTotal = cbHardwareItems.reduce((sum, row) => sum + Number(row.sales_amount || 0), 0);
    const customerOptions = cbCustomers.map(customer => `<option value="${cbEsc(customer.id)}">${cbEsc(customer.name)}</option>`).join('');
    const boardForm = quoteExists && quoteDraft ? `<section class="panel cb-bom-form"><header><div><h3>添加板材 BOM 行</h3><p>销售单价手工核定；采购参考价只保留在档案及老板专用视图。</p></div></header><form id="cbBoardBomForm"><div class="cb-bom-grid"><label>空间<input class="field" name="space" value="主卧" required></label><label>部位用途<select class="field" name="part_use">${['柜体','柜门','见光板','背板','层板','其他'].map(x => `<option>${x}</option>`).join('')}</select></label><label class="cb-wide">板材档案<select class="field" name="board_id" required>${cbBoardSelect()}</select></label><label>单位<select class="field" name="unit">${customBomLogic.units.boardBom.map(x => `<option>${x}</option>`).join('')}</select></label><label>数量<input class="field" name="quantity" type="number" min="0.001" step="0.001" value="1" required></label><label>销售单价<input class="field" name="sales_unit_price" type="number" min="0" step="0.01" value="0" required></label><label>封边工艺<select class="field" name="edge_process"><option>无</option><option>EVA</option><option>PUR</option><option>激光</option></select></label><label>封边长度（米）<input class="field" name="edge_length_m" type="number" min="0" step="0.1" value="0"></label><label>封边计价<select class="field" name="edge_charge_mode"><option value="included">已含在基础价</option><option value="separate">单列计价</option></select></label><label>封边销售价 / 米<input class="field" name="edge_sales_price_per_meter_snapshot" type="number" min="0" step="0.01" value="0"></label><label>板材利用率<input class="field" name="utilization_rate" type="number" min="0.01" max="1" step="0.01" value="1"></label><label>线性宽度（mm）<input class="field" name="linear_width_mm" type="number" min="1" step="1" placeholder="延米换算必填"></label><label class="cb-wide">备注<input class="field" name="note"></label></div><button class="btn primary" ${cbBusy ? 'disabled' : ''}>＋ 保存板材行</button></form></section>` : '';
    const firstHardware = cbCatalog.hardware.find(x => x.status !== '停用');
    const hardwareForm = quoteExists && quoteDraft ? `<section class="panel cb-bom-form"><header><div><h3>添加五金 BOM 行</h3><p>单位自动沿用五金档案；已含配套金额固定为 0，本页不提供采购成本字段。</p></div></header><form id="cbHardwareBomForm"><div class="cb-bom-grid"><label>使用位置<input class="field" name="use_location" value="主卧柜门" required></label><label class="cb-wide">五金档案<select class="field" name="hardware_id" required>${cbHardwareSelect()}</select></label><label>单位<input class="field" name="unit" value="${cbEsc(firstHardware?.unit || '')}" readonly required></label><label>数量<input class="field" name="quantity" type="number" min="0.001" step="0.001" value="1" required></label><label>销售单价<input class="field" name="sales_unit_price" type="number" min="0" step="0.01" value="0" required></label><label class="cb-check"><input type="checkbox" name="included_in_base"> 已含基础配套</label><label class="cb-wide">备注<input class="field" name="note"></label></div><button class="btn primary" ${cbBusy ? 'disabled' : ''}>＋ 保存五金行</button></form></section>` : '';
    const managerOptions = cbFactoryManagers.map(person => `<option value="${cbEsc(person.id)}">${cbEsc(person.display_name || `工厂负责人 ${person.id.slice(0, 6)}`)}</option>`).join('');
    const orderPanel = cbOwner() && quoteExists ? (quoteDraft
      ? `<section class="panel cb-order-confirm"><header><div><h3>确认转下单</h3><p>按当前报价 BOM 建立订单快照，后续修改两边互不影响。</p></div></header><div class="cb-order-controls"><label>工厂负责人<select id="cbFactoryManagerSelect" class="field" required><option value="">选择工厂负责人</option>${managerOptions}</select></label><button class="btn primary" data-action="cb-order-from-quote" ${cbBusy || !cbFactoryManagers.length ? 'disabled' : ''}>确认转下单</button></div></section>`
      : `<section class="panel cb-order-confirm"><header><div><h3>已转为生产订单</h3><p>订单 BOM 快照已锁定。报价 ${cbBoardItems.length} 板 / ${cbHardwareItems.length} 五金。</p></div></header><p>订单 BOM：板材 ${cbOrderRows.filter(row => row.item_kind === 'board').length} 行 · 五金 ${cbOrderRows.filter(row => row.item_kind === 'hardware').length} 行；来源行 ID 已保留。</p></section>`)
      : '';
    return `${head('CUSTOM QUOTATION · BOM WORKSHOP', '定制 BOM 报价与用量', '多行板材 / 五金报价、封边包含或单列、张 / ㎡ / 延米用量换算。安全视图不返回采购价和成本。', '')}
      <div class="cb-steps"><span class="cb-step done">2 · 样板档案</span><span class="cb-step done">3 · 档案与价格</span><span class="cb-step active">4 · BOM 报价</span></div>
      ${quoteExists ? `<div class="cb-quote-bar"><div><small>当前报价 · ${quoteDraft ? '草稿' : '已转单'}</small><b>${cbEsc(cbQuoteTitle || '艺匠样板户 · 多行报价')}</b><code>${cbEsc(cbQuoteId)}</code></div><button class="btn" data-action="cb-new-quote">新建报价</button><strong>销售合计 ${money(boardTotal + hardwareTotal)}</strong></div>${orderPanel}<div class="cb-bom-layout">${boardForm}${hardwareForm}</div>
      ${panel(`板材 BOM · ${cbBoardItems.length} 行`, '单位张直接计数；㎡按标准板面积换算；延米需填线性宽度。单位“米”作为长度记录，不臆算板张数。', `<div class="table-wrap"><table class="cb-table cb-bom-table"><thead><tr><th>空间</th><th>板材 / 部位</th><th>当前销售价</th><th>修改销售价</th><th>封边长度</th><th>封边方式</th><th>封边价 / 米</th><th>销售金额</th><th>板材张数估算</th><th></th></tr></thead><tbody>${cbBoardItems.map(cbBoardRow).join('') || '<tr><td colspan="10" class="cb-empty">尚无板材行</td></tr>'}</tbody></table></div>`)}
      ${panel(`五金 BOM · ${cbHardwareItems.length} 行`, '已含配套金额固定为 0；销售视图只含数量、销售单价和金额。', `<div class="table-wrap"><table class="cb-table"><thead><tr><th>位置</th><th>五金 / 规格</th><th>销售价 / 单位</th><th>是否已含</th><th>销售金额</th><th></th></tr></thead><tbody>${cbHardwareItems.map(cbHardwareRow).join('') || '<tr><td colspan="6" class="cb-empty">尚无五金行</td></tr>'}</tbody></table></div>`)}
      <div class="cb-pricing-hint"><b>封边计价：</b>已含则金额为 0；单列按“封边长度 × 封边销售价 / 米”计算。档案未提供销售价时保留 0，需按实际报价核定。<br><b>张数估算：</b>1220×2440 mm 标准板面积 ${customBomLogic.sheetAreaM2('1220×2440')} ㎡；利用率会影响估算张数。</div>` : `<section class="panel cb-create-quote"><h3>创建定制报价</h3><p>只列出当前账号允许访问的定制客户。</p><form id="cbCreateQuoteForm"><label>客户<select class="field" name="customer_id" required><option value="">${!cbCustomersLoaded || cbCustomersLoading ? '加载中…' : cbCustomers.length ? '选择客户' : '暂无可用定制客户'}</option>${customerOptions}</select></label><label>报价标题<input class="field" name="title" value="艺匠样板户 · 板材五金报价" required></label><button class="btn primary" ${!cbCustomersLoaded || !cbCustomers.length ? 'disabled' : ''}>创建草稿报价</button>${cbOwner() ? `<button type="button" class="btn" data-action="cb-import-bom" ${!cbCustomersLoaded || !cbCustomers.length ? 'disabled' : ''}>按样板创建多行演示报价</button>` : ''}</form></section>`}`;
  }

  async function cbCreateQuote(customerId, title) {
    const result = await cbClient().schema('api').rpc('custom_create_quote', { p_customer_id: customerId, p_title: title });
    if (result.error) throw result.error;
    cbQuoteId = result.data.id; cbQuoteTitle = title;
    const key = `anju-custom-bom:${window.__ANJU_AUTH__?.user?.id || 'user'}`;
    localStorage.setItem(key, JSON.stringify({ id: cbQuoteId, title, orderId: '' }));
    await cbLoadQuote();
  }
  async function cbAddBom(kind, payload) {
    const existing = kind === 'board' ? cbBoardItems : cbHardwareItems;
    const result = await cbClient().schema('api').rpc('custom_save_bom', { p_quote_id: cbQuoteId, p_kind: kind, p_data: { item_no: existing.length + 1, ...payload }, p_id: null });
    if (result.error) throw result.error;
    await cbLoadQuote();
  }
  async function cbImportBomSample() {
    if (!cbOwner()) throw new Error('样板演示报价由老板建立');
    const form = $('#cbCreateQuoteForm');
    const customerId = form?.elements.customer_id.value;
    if (!customerId) throw new Error('请先选择定制客户');
    const response = await fetch(cbDemoUrl, { cache: 'no-store' });
    if (!response.ok) throw new Error('未找到样板数据文件');
    const sample = await response.json();
    cbBusy = true; render();
    try {
      await cbCreateQuote(customerId, '艺匠样板户 · 板材五金 BOM 演示');
      for (const row of sample.board_bom) {
        const catalog = cbCatalog.board.find(item => item.material_name === row.board_name);
        if (!catalog) throw new Error(`档案缺少板材：${row.board_name}，请先导入板材样板档案`);
        const normalized = customBomLogic.normalizePartUse(row.part_use, row.note || '');
        await cbAddBom('board', { space: row.space, part_use: normalized.partUse, board_id: catalog.id, unit: row.unit, quantity: row.quantity, sales_unit_price: 0, edge_process: catalog.edge_process || '无', edge_length_m: 0, edge_charge_mode: 'included', edge_sales_price_per_meter_snapshot: 0, utilization_rate: 1, note: normalized.note });
      }
      for (const row of sample.hardware_bom) {
        const catalog = cbCatalog.hardware.find(item => item.hardware_name === row.hardware_name);
        if (!catalog) throw new Error(`档案缺少五金：${row.hardware_name}，请先导入五金样板档案`);
        await cbAddBom('hardware', { use_location: row.use_location, hardware_id: catalog.id, unit: row.unit, quantity: row.quantity, sales_unit_price: 0, included_in_base: row.included_in_base, note: '' });
      }
      cbBusy = false; render(); toast('已创建样板报价：板材 7 行、五金 6 行；销售价保持 0 待老板 / 设计师核价');
    } catch (error) { cbBusy = false; render(); toast(`样板报价未完成：${cbFail(error)}`); }
  }
  async function cbSaveBoardRow(button) {
    const row = cbBoardItems.find(item => item.id === button.dataset.id), tr = button.closest('tr');
    if (!row || !tr) return;
    const mode = $('[data-row-edge-mode]', tr).value;
    const result = await cbClient().schema('api').rpc('custom_save_bom', { p_quote_id: cbQuoteId, p_kind: 'board', p_id: row.id, p_data: { sales_unit_price: cbNumber($('[data-row-price]', tr).value), edge_length_m: cbNumber($('[data-row-edge-length]', tr).value), edge_charge_mode: mode, edge_sales_price_per_meter_snapshot: mode === 'included' ? 0 : cbNumber($('[data-row-edge-price]', tr).value) } });
    if (result.error) throw result.error;
    await cbLoadQuote(); render(); toast('板材报价行已保存');
  }
  async function cbSaveHardwareRow(button) {
    const row = cbHardwareItems.find(item => item.id === button.dataset.id), tr = button.closest('tr');
    if (!row || !tr) return;
    const result = await cbClient().schema('api').rpc('custom_save_bom', { p_quote_id: cbQuoteId, p_kind: 'hardware', p_id: row.id, p_data: { sales_unit_price: cbNumber($('[data-row-price]', tr).value), included_in_base: $('[data-row-included]', tr).checked } });
    if (result.error) throw result.error;
    await cbLoadQuote(); render(); toast('五金报价行已保存');
  }
  async function cbDeleteRow(kind, id) {
    const result = await cbClient().schema('api').rpc('custom_delete_bom', { p_quote_id: cbQuoteId, p_kind: kind, p_id: id });
    if (result.error) throw result.error;
    await cbLoadQuote(); render();
  }
  async function cbTransferQuoteToOrder(factoryManagerId) {
    if (!cbOwner()) throw new Error('仅老板可确认转下单');
    if (!factoryManagerId) throw new Error('请先选择工厂负责人');
    cbBusy = true; render();
    try {
      const result = await cbClient().schema('api').rpc('custom_order_from_quote', { p_quote_id: cbQuoteId, p_factory_manager_id: factoryManagerId });
      if (result.error) throw result.error;
      cbOrderId = result.data.id;
      await cbLoadQuote();
      await cbLoadOrderBom();
      const key = `anju-custom-bom:${window.__ANJU_AUTH__?.user?.id || 'user'}`;
      localStorage.setItem(key, JSON.stringify({ id: cbQuoteId, title: cbQuoteTitle, orderId: cbOrderId }));
      cbBusy = false; render();
      toast(result.data.status === 'existing' ? '该报价已关联生产订单，订单 BOM 已载入' : '报价已转为生产订单，板材与五金行已复制');
    } catch (error) { cbBusy = false; render(); throw error; }
  }
  function cbSetUnitFromCatalog(select) {
    if (!select) return;
    const id = select.value, form = select.closest('form');
    if (!form) return;
    const catalog = select.name === 'board_id' ? cbCatalog.board.find(x => x.id === id) : cbCatalog.hardware.find(x => x.id === id);
    if (!catalog) return;
    const unit = form.elements.unit;
    const unitValue = select.name === 'board_id' ? (catalog.pricing_method === '按㎡' ? '㎡' : catalog.pricing_method === '按延米' ? '延米' : '张') : catalog.unit;
    if (unit.tagName === 'SELECT') { if ([...unit.options].some(x => x.value === unitValue)) unit.value = unitValue; }
    else unit.value = unitValue;
    const price = form.elements.sales_unit_price;
    if (price) price.value = Number(catalog.default_sales_price || 0);
    if (select.name === 'board_id' && form.elements.edge_process) form.elements.edge_process.value = catalog.edge_process || '无';
  }
  async function cbOpenPage(target) {
    module = 'custom'; page = target;
    if (target === 'custom-bom' && !cbCustomersLoaded) cbCustomersLoading = true;
    render();
    try {
      if (!cbCatalog.board.length && !cbCatalog.hardware.length) await cbLoadCatalog();
      if (target === 'custom-bom') {
        if (!cbCustomersLoaded) {
          cbCustomersLoading = true; render();
          try { await cbLoadCustomers(); } finally { cbCustomersLoading = false; }
        }
        if (cbOwner() && !cbFactoryManagers.length) await cbLoadFactoryManagers();
        const key = `anju-custom-bom:${window.__ANJU_AUTH__?.user?.id || 'user'}`;
        const saved = JSON.parse(localStorage.getItem(key) || 'null');
        if (saved?.id) { cbQuoteId = saved.id; cbQuoteTitle = saved.title || ''; cbOrderId = saved.orderId || ''; await cbLoadQuote(); await cbLoadOrderBom(); }
      }
      render();
    } catch (error) { toast(`加载失败：${cbFail(error)}`); }
  }
  const renderBeforeCustomBom = render;
  render = function () {
    if (module === 'custom' && ['custom-catalog', 'custom-bom'].includes(page)) {
      if (role !== 'owner' && role !== 'sales') { page = 'home'; return renderBeforeCustomBom(); }
      renderNav(); $('#roleSelect').value = role;
      $('#view').innerHTML = page === 'custom-catalog' ? cbCatalogPage() : cbBomPage();
      return;
    }
    return renderBeforeCustomBom();
  };
  const setRoleBeforeCustomBom = setRole;
  setRole = function (next) {
    setRoleBeforeCustomBom(next);
    const previewRoute = new URLSearchParams(location.search).get('preview');
    if ((previewRoute === 'custom-catalog' || previewRoute === 'custom-bom') && ['owner', 'sales'].includes(role)) {
      module = 'custom'; page = previewRoute; render();
      cbOpenPage(previewRoute);
    }
  };
  document.addEventListener('click', async event => {
    const button = event.target.closest('[data-action^="cb-"]');
    if (!button) return;
    event.preventDefault(); event.stopImmediatePropagation();
    const action = button.dataset.action;
    try {
      if (action === 'cb-kind') { cbKind = button.dataset.kind; cbEditing = null; render(); }
      else if (action === 'cb-new-catalog') { cbEditing = {}; render(); }
      else if (action === 'cb-edit-catalog') { cbKind = button.dataset.kind; cbEditing = cbCatalog[cbKind].find(x => x.id === button.dataset.id) || null; render(); }
      else if (action === 'cb-cancel-edit') { cbEditing = null; render(); }
      else if (action === 'cb-import-demo') await cbImportDemo();
      else if (action === 'cb-new-quote') { cbQuoteId = ''; cbQuoteTitle = ''; cbQuoteStatus = 'draft'; cbOrderId = ''; cbOrderRows = []; cbBoardItems = []; cbHardwareItems = []; render(); }
      else if (action === 'cb-import-bom') await cbImportBomSample();
      else if (action === 'cb-order-from-quote') await cbTransferQuoteToOrder($('#cbFactoryManagerSelect')?.value);
      else if (action === 'cb-save-board-row') await cbSaveBoardRow(button);
      else if (action === 'cb-save-hardware-row') await cbSaveHardwareRow(button);
      else if (action === 'cb-delete-board-row') await cbDeleteRow('board', button.dataset.id);
      else if (action === 'cb-delete-hardware-row') await cbDeleteRow('hardware', button.dataset.id);
    } catch (error) { toast(`操作失败：${cbFail(error)}`); }
  }, true);
  document.addEventListener('change', event => {
    if (event.target.matches('#cbBoardBomForm [name="board_id"], #cbHardwareBomForm [name="hardware_id"]')) cbSetUnitFromCatalog(event.target);
    if (event.target.matches('#cbBoardBomForm [name="edge_charge_mode"]')) {
      const price = $('#cbBoardBomForm [name="edge_sales_price_per_meter_snapshot"]');
      if (price && event.target.value === 'included') price.value = '0';
    }
    if (event.target.matches('[data-row-edge-mode]')) {
      const price = event.target.closest('tr')?.querySelector('[data-row-edge-price]');
      if (price) { price.disabled = event.target.value === 'included'; if (price.disabled) price.value = '0'; }
    }
  });
  document.addEventListener('submit', async event => {
    const form = event.target;
    if (!['cbCatalogForm', 'cbCreateQuoteForm', 'cbBoardBomForm', 'cbHardwareBomForm'].includes(form.id)) return;
    event.preventDefault(); event.stopImmediatePropagation();
    if (cbBusy) return;
    cbBusy = true;
    try {
      if (form.id === 'cbCatalogForm') await cbSaveCatalog(form);
      else if (form.id === 'cbCreateQuoteForm') {
        await cbCreateQuote(form.elements.customer_id.value, form.elements.title.value.trim());
        await cbLoadCatalog(); render(); toast('定制报价草稿已创建');
      } else if (form.id === 'cbBoardBomForm') {
        const data = Object.fromEntries(new FormData(form).entries());
        const catalog = cbCatalog.board.find(x => x.id === data.board_id);
        const mode = data.edge_charge_mode;
        await cbAddBom('board', { ...data, quantity: cbNumber(data.quantity), sales_unit_price: cbNumber(data.sales_unit_price), edge_length_m: cbNumber(data.edge_length_m), edge_charge_mode: mode, edge_sales_price_per_meter_snapshot: mode === 'included' ? 0 : cbNumber(data.edge_sales_price_per_meter_snapshot), utilization_rate: cbNumber(data.utilization_rate), linear_width_mm: data.linear_width_mm ? cbNumber(data.linear_width_mm) : null, edge_process: data.edge_process || catalog?.edge_process || '无' });
        render(); toast('板材 BOM 行已保存');
      } else {
        const data = Object.fromEntries(new FormData(form).entries()), catalog = cbCatalog.hardware.find(x => x.id === data.hardware_id);
        await cbAddBom('hardware', { ...data, quantity: cbNumber(data.quantity), sales_unit_price: cbNumber(data.sales_unit_price), included_in_base: form.elements.included_in_base.checked, unit: catalog?.unit || data.unit });
        render(); toast('五金 BOM 行已保存');
      }
    } catch (error) { cbBusy = false; render(); toast(`保存失败：${cbFail(error)}`); }
    finally { cbBusy = false; }
  }, true);
  window.addEventListener('anju:auth-ready', event => {
    if (event.detail?.internalRole) {
      const route = new URLSearchParams(location.search).get('preview');
      if ((route === 'custom-catalog' || route === 'custom-bom') && ['owner', 'sales'].includes(event.detail?.internalRole)) setTimeout(() => cbOpenPage(route), 0);
    }
  });
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-page="custom-catalog"], [data-page="custom-bom"]');
    if (!button) return;
    event.preventDefault(); event.stopImmediatePropagation();
    cbOpenPage(button.dataset.page);
  }, true);
