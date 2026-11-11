// Domain: Factory / Core
// Type: include (fragment)
// Part: 1 of 6 - keep all 6 factory-cloud files adjacent and in this order in sync-quote-preview.ps1
// WARNING: This is a FRAGMENT of the factory-cloud block. It is NOT a standalone JS file
//          and will not parse on its own. Part 1 opens the block; Part 6 closes it.
// Description:
//   Block opener, fc state object, data loading (fcLoad / fcLoadCosts),
//   cloud RPC helpers, shared UI helpers (fcHead / fcTable / fcEntry),
//   tool helpers (fcMoney / fcDateVal / fcIsOwner) and stage list.
// Functions: fcLoad, fcLoadCosts, fcBanner, fcOrder, fcMoney, fcHead, fcTable, fcEntry, fcStageList, fcStageForProcess
// Note: Concatenated into framework-preview.js. Never edit framework-preview.js directly.


// Factory production and finance module. All values are read from the protected API.
{
  const fc = { loading:false, loaded:false, error:'', orders:[], safeOrders:[], employees:[], safeEmployees:[], attendance:[], inventory:[], valuation:[], movements:[], ownerMovements:[], purchaseInvoices:[], directPurchaseCosts:[], fixed:[], payroll:[], monthly:[], yearly:[], costEntries:[],costEntriesOrder:'',costEntriesLoading:false,costEntriesError:'',dossier:null,dossierOrder:'',assignmentUsers:[],selectedOrder:'',attendanceMonth:'',financeMonth:'',accounts:[],cashEntries:[],attendanceCosts:[],history:[],historyOrder:'',purchaseDraft:null,configRequestIds:new Map(),productionFilter:'生产中',inventoryCategory:'五金',attendanceExpandedDate:'',bulkInventoryDraft:null,payrollTargets:[] };
  const fcClient=()=>window.__ANJU_AUTH__?.client||null;
  const fcRpc=async(name,args={})=>{const c=fcClient();if(!c)throw Error('请先登录云端账号');const {data,error}=await c.schema('api').rpc(name,args);if(error)throw error;return data||[]};
  const fcRead=async(name)=>{const c=fcClient();if(!c)throw Error('请先登录云端账号');const {data,error}=await c.schema('api').from(name).select('*');if(error)throw error;return data||[]};
  const fcFail=e=>e?.message||e?.details||'读取失败';
  const fcToday=()=>new Date().toLocaleDateString('sv-SE');
  const fcMonth=()=>fcToday().slice(0,7);
  const fcReq=()=>crypto.randomUUID();
  const fcIsOwner=()=>role==='owner';
  const fcSafeRole=()=>['factory','designer','foreman'].includes(role);
  const fcDateVal=(d)=>String(d||'').slice(0,10);
  const fcProofButtons=docs=>(Array.isArray(docs)?docs:[]).map(d=>`<button type="button" class="btn small fc-proof-link" data-action="fc-proof-view" data-id="${esc(d.path)}">${esc(d.name||'收付款凭证')}</button>`).join('')||'—';
  async function fcLoad(force=false){
    if(!['owner','factory','designer','foreman'].includes(role)||module!=='factory'||fc.loading||fc.loaded&&!force)return;
    fc.loading=true;fc.error='';render();
    try{
      if(['designer','foreman'].includes(role)){
        const safeOrders=await fcRpc('factory_visible_work_orders');Object.assign(fc,{safeOrders,orders:[],employees:[],safeEmployees:[],attendance:[],inventory:[],movements:[],loaded:true});
      }else{
      const invoiceRows=fcIsOwner()?fcRpc('owner_factory_purchase_invoices'):role==='factory'?fcRpc('factory_purchase_invoices_safe'):Promise.resolve([]);
      const common=[fcRpc('factory_work_orders_safe'),fcRpc('factory_employees_safe'),fcRpc('factory_attendance_safe'),fcRpc('factory_inventory_quantities'),fcRpc('factory_inventory_movements_safe'),invoiceRows];
      if(fcIsOwner()){
        const payrollMonth=fc.attendanceMonth||fcMonth();
        const [safeOrders,safeEmployees,attendance,inventory,movements,purchaseInvoices,orders,employees,payroll,fixed,ownerMovements,valuation,monthly,yearly,accounts,cashEntries,attendanceCosts,assignmentUsers,payrollTargets]=await Promise.all([...common,fcRpc('owner_factory_work_orders'),fcRpc('owner_factory_employees'),fcRpc('owner_factory_payroll',{p_month:`${payrollMonth}-01`}),fcRead('owner_fixed_cost_ledger'),fcRpc('owner_factory_inventory_movements'),fcRpc('owner_factory_inventory_valuation'),fcRead('owner_monthly_net_profit'),fcRead('owner_yearly_net_profit'),fcRpc('owner_business_accounts'),fcRpc('owner_factory_cash_ledger_v3'),fcRpc('owner_factory_attendance_costs'),fcRpc('factory_assignment_users'),fcRpc('owner_factory_payroll_adjustment_targets',{p_month:`${payrollMonth}-01`})]);
        Object.assign(fc,{safeOrders,safeEmployees,attendance,inventory,movements,purchaseInvoices,orders,employees,payroll,fixed,ownerMovements,valuation,monthly,yearly,accounts,cashEntries,attendanceCosts,assignmentUsers,payrollTargets});
      }else{const [safeOrders,safeEmployees,attendance,inventory,movements,purchaseInvoices,assignmentUsers,fixed]=await Promise.all([...common,fcRpc('factory_assignment_users'),fcRpc('factory_manager_fixed_costs_v2')]);Object.assign(fc,{safeOrders,safeEmployees,attendance,inventory,movements,purchaseInvoices,assignmentUsers,fixed});}
      fc.loaded=true;} 
    }catch(e){fc.error=fcFail(e);fc.loaded=true;}finally{fc.loading=false;render();}
  }
  async function fcLoadCosts(orderId){
    if(!orderId||fc.costEntriesLoading||fc.historyOrder===orderId&&( !fcIsOwner()||fc.costEntriesOrder===orderId))return;
    fc.costEntriesLoading=true;fc.costEntriesError='';
    try{
      const [costs,history,dossier,purchaseCosts,specProfile]=await Promise.all([fcIsOwner()?fcRpc('owner_factory_order_cost_entries',{p_order_id:orderId}):Promise.resolve([]),fcRpc('factory_work_order_history_scoped',{p_order_id:orderId}),fcRpc('factory_order_dossier',{p_order_id:orderId}),['owner','factory'].includes(role)?fcRpc('factory_order_purchase_costs',{p_order_id:orderId}):Promise.resolve([]),['owner','factory'].includes(role)?fcRpc('factory_order_spec_profile',{p_order_id:orderId}):Promise.resolve([])]);
      fc.costEntries=costs;fc.directPurchaseCosts=purchaseCosts;fc.specProfile=specProfile?.[0]||null;fc.costEntriesOrder=orderId;fc.history=history;fc.historyOrder=orderId;fc.dossier=dossier;fc.dossierOrder=orderId;
    }catch(e){fc.costEntriesError=fcFail(e);}finally{fc.costEntriesLoading=false;render();}
  }
  const fcBanner=()=>fc.loading?'<div class="fc-notice">加载中…</div>':fc.error?`<div class="fc-notice error">云端读取失败：${esc(fc.error)} <button class="btn small" data-action="fc-refresh">重试</button></div>`:'';
  const fcOrder=id=>fc.orders.find(x=>x.id===id)||fc.safeOrders.find(x=>x.id===id);
  const fcMoney=v=>money(Number(v||0));
  const fcHead=(en,title,desc,actions='')=>head(en,title,desc,actions||`<button class="btn" data-action="fc-refresh">刷新</button>`);
  const fcTable=(heads,rows)=>`<div class="table-wrap"><table><thead><tr>${heads.map(h=>`<th>${h}</th>`).join('')}</tr></thead><tbody>${rows||`<tr><td colspan="${heads.length}" class="empty">暂无记录</td></tr>`}</tbody></table></div>`;
  const fcEntry=(title,value,note,glyph,target)=>`<button class="fc-entry" data-page="${target}"><span class="fc-entry-top"><b>${esc(title)}</b><i>${glyph}</i></span><strong>${value}</strong><small>${esc(note)}</small><span class="fc-entry-link">进入 →</span></button>`;
  const fcStageList=['未排产','到货待开料','开料','封边','排钻','加工','试装','打包','安装','已完工'];
  const fcStageForProcess=p=>Math.max(0,fcStageList.indexOf(p));