  // Cloud-only custom procurement, inventory, and material issue desk.
  pages.custom.push(['custom-procurement', '采购与库存', '▥'], ['custom-finance', '定制财务', '￥']);
  const cpPageIds = ['custom-procurement'];
  const canAccessBeforeProcurement = canAccessPage;
  canAccessPage = function (moduleId, pageId) {
    if (moduleId === 'custom' && cpPageIds.includes(pageId)) return role === 'owner' || role === 'factory';
    return canAccessBeforeProcurement(moduleId, pageId);
  };
  const cp = { tab: 'orders', busy: false, loading: false, loaded: false, loadError: '', orders: [], customers: [], boards: [], hardware: [], purchases: [], lines: [], allocations: [], stock: [], tx: [], costs: [], attachments: [], orderBom: [], allOrderBom: [], selectedPurchase: '', fileCustomerId: '', message: '', finance: {loaded:false,loading:false,error:'',profit:[],months:[],years:[],fixed:[],orderCosts:[],receivables:[],plans:[],payments:[]} };
  const cpClient = () => window.__ANJU_AUTH__?.client || null;
  const cpOwner = () => role === 'owner';
  const cpToday = () => new Date().toISOString().slice(0, 10);
  const cpEsc = value => esc(value);
  const cpFail = error => error?.message || error?.details || error?.hint || String(error || '请求失败');
  const cpOrderNames = () => new Map(cp.orders.map(x => [x.id, `${x.order_no || x.id.slice(0, 8)} · ${cp.customers.find(c => c.id === x.customer_id)?.name || '定制客户'}`]));
  const cpCatalogName = (kind, id) => (kind === 'board' ? cp.boards : cp.hardware).find(x => x.id === id)?.[kind === 'board' ? 'material_name' : 'hardware_name'] || id;
  const cpQuery = async (name, opts = {}) => {
    const c = cpClient(); if (!c) throw new Error('请先登录云端账号');
    let query = c.schema('api').from(name).select('*');
    if (opts.order) query = query.order(opts.order, { ascending: false });
    const { data, error } = await query;
    if (error) throw error;
    return data || [];
  };
  async function cpLoad() {
    if (!cpClient() || cp.loading) return;
    cp.loading = true; cp.loadError=''; render();
    try {
      const owner=cpOwner();
      const base = await Promise.all([
        cpQuery('factory_order_detail', { order: 'order_date' }),
        owner ? cpQuery('custom_board_catalog_sales') : cpQuery('custom_catalog_factory'),
        owner ? cpQuery('custom_hardware_catalog_sales') : Promise.resolve([]),
        owner ? cpQuery('my_customers') : Promise.resolve([]), cpQuery('custom_inventory_quantities'),
        cpQuery('custom_material_transactions', { order: 'transaction_date' }), cpQuery('custom_order_bom_factory')
      ]);
      cp.orders = base[0].filter(x => x.business_source === '门店定制');
      if(owner){cp.boards=base[1];cp.hardware=base[2];}
      else{cp.boards=base[1].filter(x=>x.catalog_kind==='board').map(x=>({id:x.catalog_id,material_name:x.item_name,unit:x.unit,status:x.status,pricing_method:x.unit==='㎡'?'按㎡':x.unit==='延米'?'按延米':'按张'}));cp.hardware=base[1].filter(x=>x.catalog_kind==='hardware').map(x=>({id:x.catalog_id,hardware_name:x.item_name,unit:x.unit,status:x.status}));}
      cp.customers = base[3].filter(x => x.business_line === 'custom'); cp.stock = base[4]; cp.tx = base[5]; cp.allOrderBom = base[6];
      if (cpOwner()) {
        const ownerData = await Promise.all([
          cpQuery('custom_purchase_review', { order: 'purchase_date' }),
          cpQuery('owner_custom_inventory_balance'), cpQuery('owner_custom_inventory_transactions', { order: 'transaction_date' }),
          cpQuery('owner_custom_cost_ledger', { order: 'occurred_at' }), cpQuery('owner_custom_purchase_allocations'),
          cpQuery('custom_attachments', { order: 'node_date' }), cpQuery('owner_custom_purchase_lines')
        ]);
        cp.purchases = ownerData[0]; cp.stock = ownerData[1]; cp.tx = ownerData[2]; cp.costs = ownerData[3]; cp.allocations = ownerData[4]; cp.attachments = ownerData[5]; cp.lines = ownerData[6];
      }
    } catch (error) { cp.loadError=cpFail(error);toast(`读取云端采购与库存失败：${cp.loadError}`); }
    finally { cp.loading = false;cp.loaded=true; render(); }
  }
  async function cpLoadFinance() {
    if (!cpClient() || role!=='owner' || cp.finance.loading) return;
    cp.finance.loading=true;cp.finance.error='';render();
    try {
      const q=cpClient().schema('api');
      const read=async(name,order)=>{let query=q.from(name).select('*');if(order)query=query.order(order,{ascending:false});const {data,error}=await query;if(error)throw error;return data||[]};
      const designer=role==='sales';
      const f=cp.finance;
      const [receivables,plans,payments]=await Promise.all([
        read(designer?'my_custom_order_receivables':'owner_custom_order_receivables','completed_at'),
        (async()=>{const {data,error}=await cpClient().from('payment_plans').select('*').order('planned_date');if(error)throw error;return data||[]})(),
        (async()=>{const {data,error}=await cpClient().from('payments').select('*').order('paid_at',{ascending:false});if(error)throw error;return data||[]})()
      ]);
      f.receivables=receivables;f.plans=plans;f.payments=payments;
      if(!designer){[f.profit,f.months,f.years,f.fixed,f.orderCosts,f.accounts]=await Promise.all([read('owner_custom_order_profit'),read('owner_monthly_net_profit','month'),read('owner_yearly_net_profit','year'),read('owner_fixed_cost_ledger','cost_month'),read('owner_custom_cost_ledger','occurred_at'),(async()=>{const {data,error}=await cpClient().schema('api').rpc('owner_business_accounts');if(error)throw error;return data||[]})()]);}
      cp.orders=receivables.map(x=>({id:x.factory_order_id,customer_id:x.customer_id,order_no:x.factory_order_id.slice(0,8),order_amount:x.order_amount,custom_quote_id:x.quote_id}));
      cp.customers=[...new Map(receivables.map(x=>[x.customer_id,{id:x.customer_id,name:x.customer_name,business_line:'custom'}])).values()];
      f.loaded=true;
    } catch(error){cp.finance.error=cpFail(error);f.loaded=true;toast(`读取定制财务失败：${cp.finance.error}`)}
    finally{cp.finance.loading=false;render()}
  }
  function cpTabs() {
    const tabs = cpOwner() ? [['orders','订单与分摊'],['purchases','采购单与附件'],['stock','库存流水'],['costs','订单成本']] : [['orders','生产订单'],['stock','库存与领退料']];
    return `<div class="cp-tabs">${tabs.map(([id,label]) => `<button class="${cp.tab===id?'active':''}" data-action="cp-tab" data-tab="${id}">${label}</button>`).join('')}</div>`;
  }
  function cpSelect(name, options, placeholder, required = false) { return `<select class="field" name="${name}" ${required?'required':''}><option value="">${placeholder}</option>${options.map(o=>`<option value="${cpEsc(o.value)}">${cpEsc(o.label)}</option>`).join('')}</select>`; }
  function cpPurchaseForm() {
    const orders = cpOrderNames();
    const catalogOptions = [...cp.boards.map(x=>({kind:'board',id:x.id,name:x.material_name,unit:x.pricing_method==='按㎡'?'㎡':x.pricing_method==='按延米'?'延米':'张',spec:[x.brand,x.thickness_mm?`${x.thickness_mm}mm`:'',x.color_name].filter(Boolean).join(' · ')})), ...cp.hardware.map(x=>({kind:'hardware',id:x.id,name:x.hardware_name,unit:x.unit,spec:[x.brand,x.spec,x.model].filter(Boolean).join(' · ')}))];
    const catalogJson = cpEsc(JSON.stringify(catalogOptions));
    return `<section class="panel cp-form"><div class="panel-head"><div><h3>新建采购单</h3><p>录入供应商、票据、运费与折让；按档案匹配品项，可将一行数量分摊至多张订单。金额仅老板可见。</p></div></div>
      <form id="cpPurchaseForm" data-catalog="${catalogJson}">
        <div class="cp-grid"><label>供应商<input class="field" name="supplier" required></label><label>单据号<input class="field" name="bill_no"></label><label>采购日期<input class="field" name="purchase_date" type="date" value="${cpToday()}" required></label><label>运费<input class="field" name="freight" type="number" min="0" step="0.01" value="0"></label><label>折让<input class="field" name="discount" type="number" min="0" step="0.01" value="0"></label><label>关联客户（附件归档）${cpSelect('attachment_customer_id',cp.customers.map(x=>({value:x.id,label:x.name})), '选择客户')}</label><label class="cp-wide">备注<input class="field" name="note"></label></div>
        <div class="cp-lines-head"><h4>采购明细</h4><button type="button" class="btn" data-action="cp-add-line">＋ 添加品项</button></div><div id="cpPurchaseLines"></div>
        <label class="cp-file-label">照片 / 单据附件<input type="file" name="files" accept="image/jpeg,image/png,image/webp,application/pdf,.xls,.xlsx" multiple></label>
        <div class="cp-actions"><button class="btn primary" ${cp.busy?'disabled':''}>保存采购单并核对</button></div>
      </form></section>`;
  }
  function cpLineMarkup(index, catalogOptions) {
    const orderOptions = cp.orders.map(o=>({value:o.id,label:cpOrderNames().get(o.id)}));
    return `<section class="cp-line" data-line-index="${index}"><header><b>采购行 ${index+1}</b><button type="button" class="btn small danger" data-action="cp-remove-line" data-index="${index}">删除</button></header>
      <div class="cp-grid"><label>匹配档案${cpSelect('catalog_id',catalogOptions.map(x=>({value:`${x.kind}:${x.id}`,label:`${x.name}${x.spec?` · ${x.spec}`:''}`})),'选择板材 / 五金档案',true)}</label><label>单位<input class="field" name="unit" readonly></label><label>数量<input class="field" name="quantity" type="number" min="0.001" step="0.001" value="1" required></label><label>采购单价<input class="field" name="purchase_unit_price" type="number" min="0" step="0.01" value="0" required></label><label>票面金额<input class="field" name="declared_amount" type="number" min="0" step="0.01" value="0" required></label><label>备注<input class="field" name="note" placeholder="票面名称差异等"></label></div>
      <div class="cp-allocation-head"><b>跨户分摊</b><button type="button" class="btn small" data-action="cp-add-allocation" data-index="${index}">＋ 添加订单</button></div><div class="cp-allocation-list"></div><small class="cp-hint">可留空入库库存；分摊数量总和不可超过采购数量。</small></section>`;
  }
  function cpAllocationMarkup() {
    return `<div class="cp-allocation-row">${cpSelect('factory_order_id',cp.orders.map(o=>({value:o.id,label:cpOrderNames().get(o.id)})),'选择订单')}<input class="field" name="allocated_quantity" type="number" min="0.001" step="0.001" placeholder="分摊数量"><select class="field" name="allocation_method"><option>手工</option><option>按BOM</option></select><button type="button" class="btn small danger" data-action="cp-remove-allocation">移除</button></div>`;
  }
  function cpPurchasePage() {
    const rows = cp.purchases.map(p=>`<tr><td><b>${cpEsc(p.supplier)}</b><small class="cb-subline">${cpEsc(p.bill_no||'无单据号')} · ${cpEsc(p.purchase_date)}</small></td><td>${cpEsc(p.status)}</td><td>${money(p.freight)}</td><td>${money(p.discount)}</td><td>${cp.attachments.filter(a=>a.purchase_order_id===p.id).length} 个</td><td><button class="btn small" data-action="cp-purchase-select" data-id="${p.id}">查看 / 推进</button></td></tr>`).join('');
    const selected = cp.purchases.find(x=>x.id===cp.selectedPurchase);
    const selectedLines = selected ? cp.lines.filter(x=>x.purchase_order_id===selected.id) : [];
    const selectedFiles = selected ? cp.attachments.filter(a=>a.purchase_order_id===selected.id) : [];
    const allocMap = new Map(cp.allocations.map(a=>[a.purchase_line_id,[]])); cp.allocations.forEach(a=>allocMap.get(a.purchase_line_id)?.push(a));
    const detail = selected ? `<section class="panel cp-detail"><div class="panel-head"><div><h3>${cpEsc(selected.supplier)} · ${cpEsc(selected.bill_no||'采购单')}</h3><p>状态：${cpEsc(selected.status)} · 运费 ${money(selected.freight)} · 折让 ${money(selected.discount)}</p></div><div class="cp-actions">${selected.status==='待核对'?`<button class="btn primary" data-action="cp-check" data-id="${selected.id}">重新核对</button>`:''}${selected.status==='已核对'?`<button class="btn primary" data-action="cp-receive" data-id="${selected.id}">确认入库</button>`:''}${selected.status==='已入库'?`<button class="btn" data-action="cp-pay" data-id="${selected.id}">登记已付款</button>`:''}</div></div><div class="table-wrap"><table class="cb-table"><thead><tr><th>匹配档案</th><th>规格快照</th><th>数量 / 单位</th><th>采购单价</th><th>计算金额</th><th>票面金额</th><th>订单分摊</th></tr></thead><tbody>${selectedLines.map(l=>`<tr><td>${cpEsc(l.item_name)}</td><td>${cpEsc(JSON.stringify(l.catalog_snapshot||{}))}</td><td>${l.quantity} ${cpEsc(l.unit)}</td><td>${money(l.purchase_unit_price)}</td><td>${money(l.line_amount)}</td><td>${money(l.declared_amount)} ${l.amount_mismatch?'<b class="cp-error">不一致</b>':'<b class="cp-ok">一致</b>'}</td><td>${(allocMap.get(l.id)||[]).map(a=>`${cpEsc(cpOrderNames().get(a.factory_order_id)||a.factory_order_id)}：${a.allocated_quantity} · ${money(a.allocated_amount)}`).join('<br>')||'库存'}</td></tr>`).join('')}</tbody></table></div><div class="cp-file-list"><b>照片 / 单据附件：</b>${selectedFiles.map(a=>`<button class="btn small" data-action="cp-attachment" data-path="${cpEsc(a.storage_path)}">${cpEsc(a.file_name)}</button>`).join(' ')||'暂无附件'}</div></section>` : '';
    return `${cpPurchaseForm()}${panel('采购单记录','只有老板可读取单价、票面金额、分摊金额；核对确认后才可入库。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>供应商 / 单据</th><th>状态</th><th>运费</th><th>折让</th><th>附件</th><th></th></tr></thead><tbody>${rows||'<tr><td colspan="6" class="cb-empty">暂无采购单</td></tr>'}</tbody></table></div>`)}${detail}`;
  }
  function cpOrderTable() {
    return `<div class="table-wrap"><table class="cb-table"><thead><tr><th>订单</th><th>客户</th><th>状态</th><th>生产阶段</th><th>生产 BOM 行</th><th></th></tr></thead><tbody>${cp.orders.map(o=>{const rows=cp.allOrderBom.filter(r=>r.factory_order_id===o.id);return `<tr><td><b>${cpEsc(o.order_no||o.id.slice(0,8))}</b><small class="cb-subline">${cpEsc(o.order_date||'')}</small></td><td>${cpEsc(cp.customers.find(c=>c.id===o.customer_id)?.name||'定制客户')}</td><td>${cpEsc(o.status)}</td><td>${cpEsc(o.current_process||'—')}</td><td>${rows.filter(x=>x.item_kind==='board').length} 板 · ${rows.filter(x=>x.item_kind==='hardware').length} 金</td><td><button class="btn small" data-action="cp-open-order" data-id="${o.id}">生产 BOM / 领料</button></td></tr>`;}).join('')||'<tr><td colspan="6" class="cb-empty">暂无可访问的定制订单</td></tr>'}</tbody></table></div>`;
  }
  function cpOrderDetail() {
    if (!cp.selectedPurchase || cp.tab!=='orders') return '';
    const order=cp.orders.find(x=>x.id===cp.selectedPurchase);if(!order)return '';
    return `<div class="cp-selected-order"><b>${cpEsc(order.order_no||order.id)}</b><small>生产数据不含报价或成本金额</small></div>`;
  }
  function cpOrderBomRows() { return cp.orderBom.map(r=>`<tr><td>${cpEsc(r.item_kind==='board'?'板材':'五金')}</td><td>${cpEsc(r.item_name)}</td><td>${cpEsc([r.brand,r.thickness_mm?`${r.thickness_mm}mm`:'',r.color_name,r.finish_process,r.edge_process].filter(Boolean).join(' · '))}</td><td>${cpEsc(r.part_use||r.space||'')}</td><td>${r.quantity} ${cpEsc(r.unit)}</td><td>${r.item_kind==='board'&&r.edge_length_m?`${r.edge_length_m} 米`:''}</td></tr>`).join('')||'<tr><td colspan="6" class="cb-empty">选择订单读取生产 BOM</td></tr>'; }
  function cpStockPage() {
    const canWrite=role==='factory';
    const balances=cp.stock.map(s=>`<tr><td>${cpEsc(s.catalog_kind==='board'?'板材':'五金')}</td><td>${cpEsc(cpCatalogName(s.catalog_kind,s.catalog_id))}</td><td>${s.quantity} ${cpEsc(s.unit)}</td>${cpOwner()?`<td>${money(s.average_unit_cost)} / ${cpEsc(s.unit)}</td>`:''}<td>${cpEsc(s.updated_at||'')}</td></tr>`).join('');
    const ledger=cp.tx.map(t=>`<tr><td>${cpEsc(t.transaction_date)}</td><td>${cpEsc(t.item_name||cpCatalogName(t.catalog_kind,t.catalog_id))}</td><td>${cpEsc(t.transaction_type)}</td><td>${t.quantity} ${cpEsc(t.unit)}</td><td>${cpEsc(t.factory_order_id?cpOrderNames().get(t.factory_order_id)||t.factory_order_id:'—')}</td>${cpOwner()?`<td>${money(t.unit_cost)} / ${cpEsc(t.unit)}</td><td>${money(t.total_cost)}</td>`:''}<td>${t.source_transaction_id?`来源 ${cpEsc(t.source_transaction_id.slice(0,8))}`:'—'}</td></tr>`).join('');
    const issueForm=canWrite?`<section class="panel cp-form"><div class="panel-head"><div><h3>登记领料数量</h3><p>只按订单、档案、数量登记；提交后仅返回成功状态。</p></div></div><form id="cpIssueForm" class="cp-grid"><label>生产订单${cpSelect('order_id',cp.orders.map(o=>({value:o.id,label:cpOrderNames().get(o.id)})),'选择本人负责订单',true)}</label><label>材料类别<select class="field" name="kind"><option value="board">板材</option><option value="hardware">五金</option></select></label><label>档案<select class="field" name="catalog_id" required></select></label><label>单位<input class="field" name="unit" readonly></label><label>可用库存<input class="field" name="stock" readonly></label><label>领料数量<input class="field" name="quantity" type="number" min="0.001" step="0.001" required></label><label>日期<input class="field" name="date" type="date" value="${cpToday()}" required></label><div class="cp-wide"><button class="btn primary">提交领料</button></div></form></section>`:'';
    const expenseForm=canWrite?`<section class="panel cp-form"><div class="panel-head"><div><h3>登记订单支出</h3><p>选择类别并填写本次支出；提交后只显示成功状态，不显示支出汇总。</p></div></div><form id="cpExpenseForm" class="cp-grid"><label>关联订单${cpSelect('order_id',cp.orders.map(o=>({value:o.id,label:cpOrderNames().get(o.id)})),'选择本人负责订单',true)}</label><label>类别<select class="field" name="category" required><option>人工</option><option>安装</option><option>外协</option><option>其他</option></select></label><label>用途<input class="field" name="description" required></label><label>发生日期<input class="field" name="date" type="date" value="${cpToday()}" required></label><label>本次支出<input class="field" name="amount" type="number" min="0.01" step="0.01" required></label><div class="cp-wide"><button class="btn primary">提交登记</button></div></form></section>`:'';
    const returnButtons=canWrite?cp.tx.filter(t=>t.transaction_type==='领料').map(t=>`<button class="btn small" data-action="cp-return" data-id="${t.id}" data-quantity="${t.quantity}" data-unit="${cpEsc(t.unit)}">登记退料</button>`):[];
    return `${issueForm}${expenseForm}${panel('可用库存',cpOwner()?'老板可查看移动加权单位成本。':'厂长仅查看库存数量。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>类别</th><th>档案</th><th>库存</th>${cpOwner()?'<th>移动加权单位成本</th>':''}<th>更新</th></tr></thead><tbody>${balances||'<tr><td colspan="5" class="cb-empty">暂无入库库存</td></tr>'}</tbody></table></div>`)}${panel('库存流水',cpOwner()?'仅老板可读单位成本与库存金额；入库、领料、退料都保留来源。':'仅显示材料、日期和数量变化。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>日期</th><th>档案</th><th>类型</th><th>数量</th><th>关联订单</th>${cpOwner()?'<th>单位成本</th><th>金额</th>':''}<th>来源</th>${canWrite?'<th>操作</th>':''}</tr></thead><tbody>${ledger||'<tr><td colspan="8" class="cb-empty">暂无库存流水</td></tr>'}</tbody></table></div>`)}`;
  }
  function cpCostsPage() {
    return panel('定制订单成本台账','老板专用；采购入库加权、领料冲减与人工费用按订单归集。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>日期</th><th>订单</th><th>类别</th><th>数量</th><th>单位成本</th><th>成本金额</th><th>备注</th></tr></thead><tbody>${cp.costs.map(c=>`<tr><td>${cpEsc(c.occurred_at)}</td><td>${cpEsc(cpOrderNames().get(c.factory_order_id)||c.factory_order_id)}</td><td>${cpEsc(c.category)}</td><td>${c.quantity} ${cpEsc(c.unit)}</td><td>${money(c.unit_cost)}</td><td>${money(c.amount)}</td><td>${cpEsc(c.note||'')}</td></tr>`).join('')||'<tr><td colspan="7" class="cb-empty">暂无订单成本记录</td></tr>'}</tbody></table></div>`);
  }
  const cpMoney=n=>money(Number(n||0));
  const cpOrderOptions=()=>cp.finance.receivables.map(o=>({value:o.factory_order_id,label:`${o.customer_name} · ${o.factory_order_id.slice(0,8)}`}));
  function cpFinancePage(){
    const owner=cpOwner(),f=cp.finance,orderById=new Map(f.receivables.map(o=>[o.factory_order_id,o]));
    if(f.loading)return `${head('CUSTOM FINANCE · 云端财务','定制财务闭环','正在读取当前账号有权查看的财务资料。',`<button class="btn" data-action="cp-finance-refresh" disabled>加载中…</button>`)}<section class="panel cp-loading" role="status">加载中…</section>`;
    if(f.error)return `${head('CUSTOM FINANCE · 云端财务','定制财务闭环','财务资料读取失败，请重试。',`<button class="btn" data-action="cp-finance-refresh">重新加载</button>`)}<section class="panel cp-error" role="alert">读取失败：${cpEsc(f.error)} <button class="btn small" data-action="cp-finance-refresh">重试</button></section>`;
    const orderByQuoteId=new Map(f.receivables.filter(o=>o.quote_id).map(o=>[o.quote_id,o]));
    const receipts=f.receivables.map(o=>`<tr><td>${cpEsc(o.customer_name)}</td><td>${cpEsc(o.order_status)}</td><td>${cpMoney(o.order_amount)}</td><td>${cpMoney(o.received_amount)}</td><td>${cpMoney(o.receivable_amount)}</td><td>${owner?cpEsc(o.factory_order_id.slice(0,8)):''}</td></tr>`).join('');
    const planRows=f.plans.filter(p=>orderById.has(p.order_id)||orderByQuoteId.has(p.quote_id)).map(p=>{const o=orderById.get(p.order_id)||orderByQuoteId.get(p.quote_id);return `<tr><td>${cpEsc(o?.customer_name||'')}</td><td>${cpEsc(p.name)}</td><td>${cpMoney(p.planned_amount)}</td><td>${cpEsc(p.planned_date||'')}</td></tr>`}).join('');
    const paymentRows=f.payments.filter(p=>orderById.has(p.order_id)||orderByQuoteId.has(p.quote_id)).map(p=>{const o=orderById.get(p.order_id)||orderByQuoteId.get(p.quote_id);return `<tr><td>${cpEsc(p.paid_at||'')}</td><td>${cpEsc(o?.customer_name||'')}</td><td>${cpMoney(p.amount)}</td><td>${cpEsc(p.method||'')}</td><td>${cpEsc(p.note||'')}</td></tr>`}).join('');
    const designerNote=owner?'':'仅显示本人负责客户的销售与收款信息。';
    if(!owner)return `${head('CUSTOM FINANCE · 客户收款','定制收款与应收',designerNote,`<button class="btn" data-action="cp-finance-refresh">刷新</button>`)}${panel('订单销售与应收','仅含本人客户的定制订单。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>客户</th><th>状态</th><th>接单额</th><th>已收</th><th>应收</th></tr></thead><tbody>${receipts||'<tr><td colspan="5" class="cb-empty">暂无本人定制订单</td></tr>'}</tbody></table></div>`)}${cpPaymentForms()}${panel('收款计划','定金、中期、尾款计划与实际收款分开列示。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>客户</th><th>阶段</th><th>计划金额</th><th>日期</th></tr></thead><tbody>${planRows||'<tr><td colspan="4" class="cb-empty">暂无收款计划</td></tr>'}</tbody></table></div>`)}${panel('实际收款流水','更正通过红冲流水保留记录。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>日期</th><th>客户</th><th>金额</th><th>方式</th><th>备注</th></tr></thead><tbody>${paymentRows||'<tr><td colspan="5" class="cb-empty">暂无收款</td></tr>'}</tbody></table></div>`)}`;
    const monthRows=f.months.map(m=>`<tr><td>${cpEsc(String(m.month).slice(0,7))}</td><td>${cpMoney(m.custom_gross)}</td><td>${cpMoney(m.factory_gross)}</td><td>${cpMoney(m.fixed_cost)}</td><td><b>${cpMoney(m.net_profit)}</b></td><td>${m.custom_completed_order_count}</td></tr>`).join('');
    const yearRows=f.years.map(y=>`<tr><td>${y.year}</td><td>${cpMoney(y.custom_gross)}</td><td>${cpMoney(y.factory_gross)}</td><td>${cpMoney(y.fixed_cost)}</td><td><b>${cpMoney(y.net_profit)}</b></td><td>${y.custom_completed_order_count}</td></tr>`).join('');
    const completed=f.profit.filter(o=>!o.is_work_in_progress),wip=f.profit.filter(o=>o.is_work_in_progress);
    const cols=['订单 / 客户','状态','接单额','板材','五金','封边','人工','安装','外协','其他','成本合计','毛利','毛利率','已分摊采购参考¹','已领料净额','差额'];
    const orderRows=rows=>rows.map(o=>`<tr><td>${cpEsc(orderById.get(o.factory_order_id)?.customer_name||o.factory_order_id.slice(0,8))}<small class="cb-subline">${cpEsc(o.factory_order_id.slice(0,8))}</small></td><td>${cpEsc(o.status)}${o.completed_at?` · ${cpEsc(String(o.completed_at).slice(0,10))}`:''}</td><td>${cpMoney(o.sales_amount)}</td><td>${cpMoney(o.board_cost)}</td><td>${cpMoney(o.hardware_cost)}</td><td>${cpMoney(o.edge_cost)}</td><td>${cpMoney(o.labor_cost)}</td><td>${cpMoney(o.installation_cost)}</td><td>${cpMoney(o.outsourcing_cost)}</td><td>${cpMoney(o.other_cost)}</td><td>${cpMoney(o.cost_total)}</td><td>${cpMoney(o.gross_profit)}</td><td>${o.gross_margin==null?'—':(Number(o.gross_margin)*100).toFixed(2)+'%'}</td><td>${cpMoney(o.allocated_purchase_reference)}</td><td>${cpMoney(o.issued_material_net_cost)}</td><td>${cpMoney(o.reconciliation_difference)}</td></tr>`).join('');
    const ownerActions=`<section class="panel cp-form"><h3>订单完工与人工类成本</h3><p>固定月薪走固定成本；按单人工走订单成本；同一笔人工不重复登记。</p><form id="cpOwnerCostForm" class="cp-grid"><label>订单${cpSelect('order_id',cpOrderOptions(),'选择订单',true)}</label><label>类别<select class="field" name="category"><option>人工</option><option>安装</option><option>外协</option><option>其他</option></select></label><label>金额<input class="field" name="amount" type="number" min="0.01" step="0.01" required></label><label>说明<input class="field" name="note"></label><button class="btn primary">登记订单成本</button></form><form id="cpCompletionForm" class="cp-grid"><label>订单${cpSelect('order_id',cpOrderOptions(),'选择订单',true)}</label><label>完工日期<input class="field" name="date" type="date" value="${cpToday()}" required></label><label>说明<input class="field" name="note"></label><button class="btn primary">标记完工</button><button type="button" class="btn" data-action="cp-reopen-order">重开所选订单</button></form></section>`;
    const fixedForm=`<section class="panel cp-form"><h3>固定成本</h3><form id="cpFixedForm" class="cp-grid"><label>月份<input class="field" name="month" type="month" value="${cpToday().slice(0,7)}" required></label><label>类别<select class="field" name="category">${['房租','水电','固定人工','折旧','办公软件','营销推广','其他'].map(x=>`<option>${x}</option>`).join('')}</select></label><label>金额<input class="field" name="amount" type="number" min="0.01" step="0.01" required></label><label>项目<input class="field" name="item"></label><label>归属<input class="field" name="ownership"></label><label>说明<input class="field" name="note"></label><button class="btn primary">登记固定成本</button></form><p>固定月薪走固定成本；按单人工走订单成本，不重复登记。</p></section>`;
    const fixedRows=f.fixed.map(x=>`<tr><td>${cpEsc(String(x.cost_month).slice(0,7))}</td><td>${cpEsc(x.category)}</td><td>${cpMoney(x.amount)}</td><td>${cpEsc(x.item||'')}</td><td>${cpEsc(x.ownership||'')}</td><td>${cpEsc(x.note||'')}</td><td>${x.reverses_id?'红冲':''}</td><td>${!x.reverses_id&&!f.fixed.some(y=>y.reverses_id===x.id)?`<button class="btn small" data-action="cp-correct-fixed" data-id="${x.id}">更正</button>`:''}</td></tr>`).join('');
    const orderCostRows=f.orderCosts.filter(x=>!x.source_transaction_id&&!x.edge_rate_id).map(x=>`<tr><td>${cpEsc(orderById.get(x.factory_order_id)?.customer_name||x.factory_order_id.slice(0,8))}</td><td>${cpEsc(x.occurred_at)}</td><td>${cpEsc(x.category)}</td><td>${cpMoney(x.amount)}</td><td>${cpEsc(x.note||'')}</td><td>${x.reverses_entry_id?'红冲':''}</td><td>${!x.reverses_entry_id&&!f.orderCosts.some(y=>y.reverses_entry_id===x.id)?`<button class="btn small" data-action="cp-correct-order-cost" data-id="${x.id}">更正</button>`:''}</td></tr>`).join('');
    return `${head('CUSTOM FINANCE · 老板专属','定制财务闭环','定制订单仅完工当月结转；在制累计不计入月净利。¹ 采购分摊仅作对账参考，不进成本与毛利。',`<button class="btn" data-action="cp-finance-refresh">刷新</button>`)}<div class="cp-finance-note">采购分摊金额仅用于对账追溯；库存材料在实际领料时计入订单成本，退料冲回。${cpMoney(wip.reduce((n,o)=>n+Number(o.cost_total||0),0))} 为在制订单累计投入。</div>${panel('定制月净利',yjAccountNotice,yjAccountTable(f.accounts,'custom'))}${panel('定制年净利','仅汇总定制业务。',yjAccountTable(f.accounts,'custom','year'))}${ownerActions}${fixedForm}${panel(`已完工订单 · ${completed.length} 单`,'七类成本按数据库台账汇总。',`<div class="table-wrap"><table class="cb-table"><thead><tr>${cols.map(c=>`<th>${c}</th>`).join('')}</tr></thead><tbody>${orderRows(completed)||'<tr><td colspan="16">暂无完工订单</td></tr>'}</tbody></table></div>`)}${panel(`在制订单 · ${wip.length} 单`,'累计成本作为在制投入，暂不进入月净利。',`<div class="table-wrap"><table class="cb-table"><thead><tr>${cols.map(c=>`<th>${c}</th>`).join('')}</tr></thead><tbody>${orderRows(wip)||'<tr><td colspan="16">暂无在制订单</td></tr>'}</tbody></table></div>`)}${panel('订单收款与应收','接单快照、实收净额与剩余应收。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>客户</th><th>状态</th><th>接单额</th><th>已收</th><th>应收</th><th>订单</th></tr></thead><tbody>${receipts}</tbody></table></div>`)}${cpPaymentForms()}${panel('定金 / 中期 / 尾款计划','收款计划不替代实际到账流水。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>客户</th><th>阶段</th><th>计划金额</th><th>日期</th></tr></thead><tbody>${planRows}</tbody></table></div>`)}${panel('订单成本更正留痕','仅人工、安装、外协、其他可在原流水基础上红冲并追加更正；领料、退料与封边流水保留原值。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>客户</th><th>日期</th><th>类别</th><th>金额</th><th>说明</th><th>冲正</th><th>操作</th></tr></thead><tbody>${orderCostRows||'<tr><td colspan="7">暂无可更正的人工类成本</td></tr>'}</tbody></table></div>`)}${panel('固定成本更正留痕','更正通过负向红冲追加；原记录保留。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>月份</th><th>类别</th><th>金额</th><th>项目</th><th>归属</th><th>说明</th><th>冲正</th><th>操作</th></tr></thead><tbody>${fixedRows}</tbody></table></div>`)}${panel('实际收款流水','原流水保留，更正通过追加反向流水。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>日期</th><th>客户</th><th>金额</th><th>方式</th><th>备注</th></tr></thead><tbody>${paymentRows}</tbody></table></div>`)}`;
  }
  function cpPaymentForms(){return `<section class="panel cp-form"><h3>登记收款计划与到账</h3><form id="cpPlanForm" class="cp-grid"><label>订单${cpSelect('order_id',cpOrderOptions(),'选择订单',true)}</label><label>阶段<select class="field" name="name"><option>定金</option><option>中期</option><option>尾款</option></select></label><label>计划金额<input class="field" name="amount" type="number" min="0" step="0.01" required></label><label>计划日期<input class="field" name="date" type="date" required></label><button class="btn">保存计划</button></form><form id="cpPaymentForm" class="cp-grid"><label>订单${cpSelect('order_id',cpOrderOptions(),'选择订单',true)}</label><label>到账金额<input class="field" name="amount" type="number" step="0.01" required></label><label>日期<input class="field" name="date" type="date" value="${cpToday()}" required></label><label>方式<select class="field" name="method"><option>微信</option><option>支付宝</option><option>银行转账</option><option>现金</option><option>其他</option></select></label><label>备注<input class="field" name="note"></label><button class="btn primary">登记到账</button></form></section>`}
  function cpPage() {
    const title=cpOwner()?'定制采购与库存':'订单物料与库存';
    const subtitle=cpOwner()?'云端采购单、附件、人工核对、订单分摊、入库及成本流水。':'生产订单、可用库存、领料与退料。';
    const body=cp.tab==='purchases'&&cpOwner()?cpPurchasePage():cp.tab==='stock'?cpStockPage():cp.tab==='costs'&&cpOwner()?cpCostsPage():`${panel(cpOwner()?'生产订单与跨户分摊':'本人负责的定制订单','采购行可分摊到多个订单；生产页只显示生产规格与数量。',cpOrderTable())}${cp.selectedPurchase&&cp.orderBom.length?panel(`订单生产 BOM · ${cp.orderBom.length} 行`,'只含生产需要的规格、部位、工艺与数量，不含销售或成本字段。',`<div class="table-wrap"><table class="cb-table"><thead><tr><th>类型</th><th>名称</th><th>生产规格 / 工艺</th><th>部位</th><th>数量 / 单位</th><th>封边长度</th></tr></thead><tbody>${cpOrderBomRows()}</tbody></table></div>`):''}`;
    return `${head('CUSTOM PROCUREMENT · 云端权限工作台',title,subtitle,`<button class="btn" data-action="cp-refresh" ${cp.loading?'disabled':''}>刷新云端数据</button>`)}<div class="cb-steps"><span class="cb-step done">5 · 订单快照</span><span class="cb-step active">6 · 采购与库存</span>${cpOwner()?'<span class="cb-step">7 · 财务闭环</span>':''}</div>${cpTabs()}${cp.loading?'<section class="panel cp-loading" role="status">加载中…正在读取云端订单与库存。</section>':''}${cp.loadError?`<section class="panel cp-error" role="alert">读取失败：${cpEsc(cp.loadError)} <button class="btn small" data-action="cp-refresh">重试</button></section>`:''}${body}`;
  }
  const renderBeforeProcurement = render;
  render = function () {
    if(module==='custom'&&page==='custom-finance'){
      if(role!=='owner'){page='home';return renderBeforeProcurement();}
      renderNav();$('#roleSelect').value=role;$('#view').innerHTML=cpFinancePage();
      if(!cp.loading&&!cp.finance.loaded){cp.finance.loaded=true;cpLoadFinance();}
      return;
    }
    if (module==='custom'&&page==='custom-procurement') {
      if (role!=='owner'&&role!=='factory') { page='home'; return renderBeforeProcurement(); }
      renderNav(); $('#roleSelect').value=role; $('#view').innerHTML=cpPage(); cpSyncForms(); return;
    }
    return renderBeforeProcurement();
  };
  cp.orderBom=[];
  function cpSyncForms() {
    const form=$('#cpPurchaseForm'); if(form&&!form.dataset.renderedLines){ form.dataset.renderedLines='1'; cpRenderLines(form); }
    const issue=$('#cpIssueForm'); if(issue) cpUpdateIssueOptions(issue);
  }
  function cpRenderLines(form) {
    const lineRoot=$('#cpPurchaseLines',form); if(!lineRoot)return;
    let count=Number(form.dataset.lineCount||0); if(!count)count=1;
    const catalogOptions=JSON.parse(form.dataset.catalog||'[]');
    lineRoot.innerHTML=Array.from({length:count},(_,i)=>cpLineMarkup(i,catalogOptions)).join(''); form.dataset.lineCount=String(count);
  }
  function cpUpdateIssueOptions(form) {
    const kind=form.elements.kind?.value||'board', select=form.elements.catalog_id, current=select.value;
    const items=(kind==='board'?cp.boards:cp.hardware).filter(x=>x.status!=='停用');
    select.innerHTML=`<option value="">选择档案</option>${items.map(x=>`<option value="${x.id}">${cpEsc(kind==='board'?x.material_name:x.hardware_name)}</option>`).join('')}`;
    if(items.some(x=>x.id===current))select.value=current;
    const item=items.find(x=>x.id===select.value); const balance=cp.stock.find(x=>x.catalog_kind===kind&&x.catalog_id===item?.id&&x.unit===(item?.unit||'张'));
    form.elements.unit.value=item?(kind==='board'?(item.pricing_method==='按㎡'?'㎡':item.pricing_method==='按延米'?'延米':'张'):item.unit):'';
    const exact=cp.stock.find(x=>x.catalog_kind===kind&&x.catalog_id===item?.id&&x.unit===form.elements.unit.value);
    form.elements.stock.value=exact?`${exact.quantity} ${exact.unit}`:'0';
  }
  async function cpRpc(name,args){const {data,error}=await cpClient().schema('api').rpc(name,args);if(error)throw error;return data;}
  async function cpSavePurchase(form) {
    const d=new FormData(form), lines=[];
    if(form.elements.files?.files?.length&&!d.get('attachment_customer_id'))throw new Error('上传采购附件前请选择归档客户');
    for(const row of $$('.cp-line',form)){
      const value=name=>row.querySelector(`[name="${name}"]`)?.value||'';
      const [kind,id]=value('catalog_id').split(':'); if(!kind||!id)throw new Error('每行都要匹配板材或五金档案');
      const item=(kind==='board'?cp.boards:cp.hardware).find(x=>x.id===id);if(!item)throw new Error('所选档案已不可用');
      const quantity=Number(value('quantity')),price=Number(value('purchase_unit_price')),declared=Number(value('declared_amount'));
      const allocations=$$('.cp-allocation-row',row).map(a=>{const get=name=>a.querySelector(`[name="${name}"]`)?.value||'';return {factory_order_id:get('factory_order_id'),allocated_quantity:Number(get('allocated_quantity')),allocation_method:get('allocation_method')}});
      if(Math.round(quantity*price*100)!==Math.round(declared*100))throw new Error(`${item.material_name||item.hardware_name}：数量 × 单价与票面金额不一致，请先核对`);
      if(allocations.some(a=>!a.factory_order_id||!a.allocated_quantity))throw new Error('请补齐跨户分摊的订单和数量');
      if(allocations.reduce((sum,a)=>sum+a.allocated_quantity,0)>quantity+0.0001)throw new Error('分摊数量超过采购数量');
      lines.push({board_id:kind==='board'?id:null,hardware_id:kind==='hardware'?id:null,temporary_item:false,item_name:kind==='board'?item.material_name:item.hardware_name,brand:item.brand||'',spec:kind==='board'?`${item.substrate||''} ${item.thickness_mm||''}mm ${item.color_name||''}`:[item.spec,item.model].filter(Boolean).join(' '),unit:value('unit'),quantity,purchase_unit_price:price,declared_amount:declared,note:value('note'),allocations});
    }
    const data={supplier:d.get('supplier'),bill_no:d.get('bill_no')||'',purchase_date:d.get('purchase_date'),freight:Number(d.get('freight')||0),discount:Number(d.get('discount')||0),note:d.get('note')||'',lines};
    cp.busy=true;form.querySelector('[type="submit"]')?.setAttribute('disabled','disabled');
    try{
      const saved=await cpRpc('custom_save_purchase',{p_data:data,p_id:null});
      cp.selectedPurchase=saved.id; await cpRpc('custom_purchase_check',{p_id:saved.id});
      await cpUploadAttachments(form,saved.id,d.get('attachment_customer_id'));
      await cpLoad();cp.tab='purchases';cp.selectedPurchase=saved.id;render();toast('采购单已保存并核对；可确认入库');
    }catch(error){toast(`采购单已保存或核对失败：${cpFail(error)}`);await cpLoad();cp.tab='purchases';render();}
    finally{cp.busy=false;render();}
  }
  async function cpUploadAttachments(form,purchaseId,customerId) {
    const files=[...(form.elements.files?.files||[])];if(!files.length)return;
    if(!customerId)throw new Error('上传采购附件前请选择归档客户');
    for(const file of files){
      const mime=file.type||({jpg:'image/jpeg',jpeg:'image/jpeg',png:'image/png',webp:'image/webp',pdf:'application/pdf',xls:'application/vnd.ms-excel',xlsx:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}[file.name.split('.').pop().toLowerCase()]||'application/octet-stream');
      const reserved=await cpRpc('custom_register_attachment',{p_data:{customer_id:customerId,purchase_order_id:purchaseId,node_date:cpToday(),document_kind:'purchase',file_name:file.name,mime_type:mime,file_size:file.size}});
      const {error}=await cpClient().storage.from('custom-files').upload(reserved.storage_path,file,{contentType:file.type,upsert:false});if(error)throw error;
    }
  }
  async function cpRunAction(action,id) {
    if(action==='cp-check')await cpRpc('custom_purchase_check',{p_id:id});
    else if(action==='cp-receive')await cpRpc('custom_purchase_receive',{p_id:id});
    else if(action==='cp-pay')await cpRpc('custom_purchase_pay',{p_id:id});
    cp.selectedPurchase=id;await cpLoad();cp.tab='purchases';render();toast('采购单状态已更新');
  }
  async function cpOpenOrder(id) {
    cp.selectedPurchase=id; cp.orderBom=[];
    try{cp.orderBom=cp.allOrderBom.filter(r=>r.factory_order_id===id);}
    catch(error){toast(`读取生产 BOM 失败：${cpFail(error)}`)} render();
  }
  document.addEventListener('click',async event=>{
    const button=event.target.closest('[data-action^="cp-"]');if(!button)return;event.preventDefault();event.stopImmediatePropagation();
    const action=button.dataset.action;
    try{
      if(action==='cp-tab'){cp.tab=button.dataset.tab;cp.selectedPurchase='';cp.orderBom=[];render();if(!cp.orders.length)await cpLoad();}
      else if(action==='cp-finance-refresh'){cp.finance.loaded=false;await cpLoadFinance();}
      else if(action==='cp-reopen-order'){
        const form=$('#cpCompletionForm'),id=form?.elements.order_id.value;if(!id)throw new Error('请先选择订单');
        const note=prompt('填写重开原因');if(note===null)return;
        const result=await cpRpc('custom_owner_reopen_order',{p_order_id:id,p_note:note,p_request_id:crypto.randomUUID()});toast(`重开提交成功：${result?.status||'完成'}`);cp.finance.loaded=false;await cpLoadFinance();
      }
      else if(action==='cp-correct-order-cost'){
        const row=cp.finance.orderCosts.find(x=>x.id===button.dataset.id);if(!row)return;
        const amount=Number(prompt('输入更正后的数值',String(row.amount)));if(!amount)return;
        const category=prompt('输入类别：人工、安装、外协、其他',row.category);if(!['人工','安装','外协','其他'].includes(category))throw new Error('成本类别无效');
        const note=prompt('填写更正说明');if(note===null)return;
        const result=await cpRpc('custom_owner_correct_order_cost',{p_entry_id:row.id,p_new_category:category,p_new_amount:amount,p_note:note,p_request_id:crypto.randomUUID()});toast(`订单成本更正成功：${result?.status||'完成'}`);cp.finance.loaded=false;await cpLoadFinance();
      }
      else if(action==='cp-correct-fixed'){
        const row=cp.finance.fixed.find(x=>x.id===button.dataset.id);if(!row)return;
        const amount=Number(prompt('输入更正后的数值',String(row.amount)));if(!amount)return;
        const result=await cpRpc('custom_owner_save_fixed_cost',{p_id:row.id,p_cost_month:row.cost_month,p_category:row.category,p_amount:amount,p_item:row.item||'',p_ownership:row.ownership||'',p_note:prompt('更正说明')||'',p_request_id:crypto.randomUUID()});toast(`固定成本更正成功：${result?.status||'完成'}`);cp.finance.loaded=false;await cpLoadFinance();
      }
      else if(action==='cp-refresh')await cpLoad();
      else if(action==='cp-add-line'){const form=$('#cpPurchaseForm'),root=$('#cpPurchaseLines',form),n=Number(form.dataset.lineCount||1);root.insertAdjacentHTML('beforeend',cpLineMarkup(n,JSON.parse(form.dataset.catalog||'[]')));form.dataset.lineCount=String(n+1);}
      else if(action==='cp-remove-line'){const form=$('#cpPurchaseForm'),root=$('#cpPurchaseLines',form),row=button.closest('.cp-line');if($$('.cp-line',root).length>1)row.remove();else{row.querySelectorAll('input').forEach(input=>{if(input.name==='quantity')input.value='1';else if(input.name==='purchase_unit_price'||input.name==='declared_amount')input.value='0';else input.value=''});row.querySelector('[name="catalog_id"]').value='';row.querySelector('.cp-allocation-list').innerHTML=''}$$('.cp-line',root).forEach((line,index)=>{line.querySelector('header b').textContent=`采购行 ${index+1}`;line.querySelector('[data-action="cp-remove-line"]').dataset.index=String(index)});form.dataset.lineCount=String($$('.cp-line',root).length);}
      else if(action==='cp-add-allocation'){button.closest('.cp-line').querySelector('.cp-allocation-list').insertAdjacentHTML('beforeend',cpAllocationMarkup());}
      else if(action==='cp-remove-allocation')button.closest('.cp-allocation-row').remove();
      else if(action==='cp-purchase-select'){cp.selectedPurchase=button.dataset.id;render();}
      else if(action==='cp-attachment'){const {data,error}=await cpClient().storage.from('custom-files').createSignedUrl(button.dataset.path,60);if(error)throw error;const link=document.createElement('a');link.href=data.signedUrl;link.target='_blank';link.rel='noopener';link.click();}
      else if(['cp-check','cp-receive','cp-pay'].includes(action))await cpRunAction(action,button.dataset.id);
      else if(action==='cp-open-order')await cpOpenOrder(button.dataset.id);
      else if(action==='cp-return'){
        const quantity=Number(prompt(`退料数量（最多 ${button.dataset.quantity} ${button.dataset.unit}）`));if(!quantity)return;
        const result=await cpRpc('custom_material_return',{p_source_transaction_id:button.dataset.id,p_quantity:quantity,p_date:cpToday(),p_request_id:crypto.randomUUID()});
        await cpLoad();toast(`退料提交成功：${result?.status||'完成'}`);
      }
    }catch(error){toast(`操作失败：${cpFail(error)}`)}
  },true);
  document.addEventListener('change',event=>{
    if(event.target.matches('.cp-line [name="catalog_id"]')){const row=event.target.closest('.cp-line'),[kind,id]=event.target.value.split(':'),item=(kind==='board'?cp.boards:cp.hardware).find(x=>x.id===id);row.querySelector('[name="unit"]').value=item?(kind==='board'?(item.pricing_method==='按㎡'?'㎡':item.pricing_method==='按延米'?'延米':'张'):item.unit):'';if(item){const qty=Number(row.querySelector('[name="quantity"]').value||0);row.querySelector('[name="declared_amount"]').value=(qty*Number(row.querySelector('[name="purchase_unit_price"]').value||0)).toFixed(2)}}
    if(event.target.matches('.cp-line [name="quantity"], .cp-line [name="purchase_unit_price"]')){const row=event.target.closest('.cp-line');row.querySelector('[name="declared_amount"]').value=(Number(row.querySelector('[name="quantity"]').value||0)*Number(row.querySelector('[name="purchase_unit_price"]').value||0)).toFixed(2)}
    if(event.target.matches('#cpIssueForm [name="kind"], #cpIssueForm [name="catalog_id"]'))cpUpdateIssueOptions(event.target.form);
  });
  document.addEventListener('submit',async event=>{
    const form=event.target;
    if(form.id==='cpPurchaseForm'){event.preventDefault();event.stopImmediatePropagation();if(cp.busy)return;await cpSavePurchase(form);return;}
    if(form.id==='cpIssueForm'){event.preventDefault();event.stopImmediatePropagation();try{const f=new FormData(form);const data=await cpRpc('custom_material_issue',{p_order_id:f.get('order_id'),p_kind:f.get('kind'),p_catalog_id:f.get('catalog_id'),p_quantity:Number(f.get('quantity')),p_unit:f.get('unit'),p_date:f.get('date'),p_request_id:crypto.randomUUID()});await cpLoad();toast(`领料提交成功：${data?.status||'完成'}`)}catch(error){toast(`领料失败：${cpFail(error)}`)}return;}
    if(form.id==='cpExpenseForm'){event.preventDefault();event.stopImmediatePropagation();try{const f=new FormData(form);const data=await cpRpc('custom_factory_record_cost',{p_order_id:f.get('order_id'),p_category:f.get('category'),p_quantity:1,p_unit:'笔',p_unit_cost:Number(f.get('amount')),p_note:`${f.get('description')}｜${f.get('date')}`,p_request_id:crypto.randomUUID()});form.reset();await cpLoad();toast(`登记成功：${data?.status||'完成'}`)}catch(error){toast(`登记失败：${cpFail(error)}`)}return;}
    if(['cpOwnerCostForm','cpFixedForm','cpCompletionForm','cpPlanForm','cpPaymentForm'].includes(form.id)){
      event.preventDefault();event.stopImmediatePropagation();try{const d=new FormData(form),req=crypto.randomUUID();let result;
        if(form.id==='cpOwnerCostForm')result=await cpRpc('custom_owner_record_order_cost',{p_order_id:d.get('order_id'),p_category:d.get('category'),p_amount:Number(d.get('amount')),p_note:d.get('note')||'',p_request_id:req});
        if(form.id==='cpFixedForm')result=await cpRpc('custom_owner_save_fixed_cost',{p_id:null,p_cost_month:`${d.get('month')}-01`,p_category:d.get('category'),p_amount:Number(d.get('amount')),p_item:d.get('item')||'',p_ownership:d.get('ownership')||'',p_note:d.get('note')||'',p_request_id:req});
        if(form.id==='cpCompletionForm')result=await cpRpc('custom_owner_complete_order',{p_order_id:d.get('order_id'),p_completed_at:new Date(`${d.get('date')}T12:00:00`).toISOString(),p_note:d.get('note')||'',p_request_id:req});
        if(form.id==='cpPlanForm'){const o=cp.finance.receivables.find(x=>x.factory_order_id===d.get('order_id'));result=await cpRpc('custom_save_payment_plan',{p_customer_id:o.customer_id,p_quote_id:o.quote_id,p_order_id:o.factory_order_id,p_name:d.get('name'),p_amount:Number(d.get('amount')),p_planned_date:d.get('date'),p_sort_order:0,p_request_id:req});}
        if(form.id==='cpPaymentForm'){const o=cp.finance.receivables.find(x=>x.factory_order_id===d.get('order_id'));result=await cpRpc('custom_record_payment',{p_customer_id:o.customer_id,p_quote_id:o.quote_id,p_order_id:o.factory_order_id,p_amount:Number(d.get('amount')),p_paid_at:d.get('date'),p_method:d.get('method'),p_note:d.get('note')||'',p_request_id:req});}
        toast(`提交成功：${result?.status||'完成'}`);form.reset();if(form.id==='cpFixedForm')form.elements.month.value=cpToday().slice(0,7);if(form.id==='cpCompletionForm')form.elements.date.value=cpToday();if(form.id==='cpPaymentForm')form.elements.date.value=cpToday();cp.finance.loaded=false;await cpLoadFinance();
      }catch(error){toast(`提交失败：${cpFail(error)}`)}return;
    }
  },true);
  document.addEventListener('click',event=>{
    const financeLink=event.target.closest('[data-page="custom-finance"]');if(financeLink){event.preventDefault();event.stopImmediatePropagation();module='custom';page='custom-finance';cp.finance.loaded=false;render();return;}
    const button=event.target.closest('[data-page="custom-procurement"]');if(!button)return;event.preventDefault();event.stopImmediatePropagation();module='custom';page='custom-procurement';cp.tab=role==='owner'?'orders':'orders';render();cpLoad();
  },true);
  const setRoleBeforeProcurement=setRole;
  setRole=function(next){setRoleBeforeProcurement(next);if(new URLSearchParams(location.search).get('preview')==='custom-procurement'){module='custom';page='custom-procurement';render();cpLoad();}};
