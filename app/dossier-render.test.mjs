import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const read=name=>fs.readFileSync(new URL(name,import.meta.url),'utf8');
const common={esc:value=>String(value??''),money:value=>`¥${value}`,head:(a,b,c,d='')=>`<h1>${b}</h1>${c}${d}`,panel:(title,desc,body)=>`<section><h2>${title}</h2>${desc}${body}</section>`,metric:(label,value)=>`<article>${label} ${value}</article>`};
const customer={id:'customer',name:'演示客户',community:'演示小区',business_status:'已签约'};
const quote={id:'quote',customer_id:'customer',quote_no:'Q-ONE',version:1,status:'草稿',total_amount:700};
const order={id:'order',customer_id:'customer',quote_id:'quote',status:'施工中',current_stage:'水电改造'};

test('owner household opens with quotes, contract, receipts, costs, stages and follow-ups',()=>{
  const source=read('reno-cloud-owner.inc.js');
  const snippet=source.slice(source.indexOf('  function rcCustomerPage()'),source.indexOf('  function rcFinancePage()'));
  const rc={selectedCustomer:'customer',customers:[customer],quotes:[quote],orders:[order],followups:[{customer_id:'customer',content:'跟进内容'}],profile:null,finance:[{order_id:'order',contract_amount:700,direct_cost_total:100,received_amount:200,receivable_amount:500,gross_profit:600}],costs:[{order_id:'order',item_name:'瓷砖材料'}],plans:[],payments:[],stages:[{id:'stage',order_id:'order',seq:3,name:'水电改造',status:'进行中'}],photos:[{order_stage_id:'stage',file_name:'现场图.png'}]};
  const ctx={...common,rc,rcAssignmentField:()=>'',rcCustomer:id=>rc.customers.find(c=>c.id===id),rcOrder:id=>rc.orders.find(o=>o.id===id),rcQuotesForCustomer:id=>rc.quotes.filter(q=>q.customer_id===id),rcOrdersForCustomer:id=>rc.orders.filter(o=>o.customer_id===id),rcFollowupsForCustomer:id=>rc.followups.filter(f=>f.customer_id===id),rcMoney:common.money};
  vm.runInNewContext(snippet,ctx);
  const html=ctx.rcCustomerPage();
  for(const label of ['Q-ONE','合同金额','瓷砖材料','登记收款','水电改造','现场图.png','跟进内容'])assert.ok(html.includes(label),`Missing household content: ${label}`);
});

test('owner can retry a failed customer profile request for the same customer',async()=>{
  const source=read('reno-cloud-owner.inc.js');
  const start=source.indexOf('  async function rcLoadProfile('),end=source.indexOf('  const rcStatus=',start);
  const replies=[{error:{message:'temporary read failure'}},{data:[{customer_id:'customer',needs:'云端需求已加载'}]}];
  const rc={profile:null,profileLoading:false};let renders=0;
  const ctx={rc,render:()=>renders++,rcFail:e=>e?.message||String(e),rcClient:()=>({schema:()=>({rpc:async()=>replies.shift()})})};
  vm.runInNewContext(source.slice(start,end),ctx);
  await ctx.rcLoadProfile('customer');
  assert.equal(rc.profile.error,'temporary read failure');
  await ctx.rcLoadProfile('customer',true);
  assert.equal(rc.profile.needs,'云端需求已加载');
  assert.equal(renders,2);
});

test('designer household opens historical quotes and shows assigned site progress without costs',()=>{
  const source=read('reno-cloud-staff.inc.js');
  const snippet=source.slice(source.indexOf('  function rsDesignerCustomer()'),source.indexOf('  const rsForm='));
  const rs={selectedCustomer:'customer',selectedOrder:'order',profileCustomer:'customer',assignments:[],quotes:[quote],orders:[order],followups:[],receivables:[{order_id:'order',contract_amount:700,received_amount:200,receivable_amount:500}],plans:[],payments:[],stages:[{id:'stage',order_id:'order',seq:3,name:'水电改造',status:'进行中',note:'现场处理说明'}],photos:[{order_stage_id:'stage',file_name:'现场图.png',storage_path:'safe-photo'}],profile:{customer_id:'customer',needs:'改善收纳',documents:[{kind:'纸质合同',file_name:'合同.pdf',path:'safe-document'}]}};
  const ctx={...common,rs,rsCustomer:()=>customer,rsOrder:()=>order,rsMoney:common.money,rsBanner:()=>'',rsTable:(heads,rows)=>heads.join('')+rows,rsStages:id=>rs.stages.filter(s=>s.order_id===id)};
  vm.runInNewContext(snippet,ctx);
  const html=ctx.rsDesignerCustomer(),orderHtml=ctx.rsDesignerOrder();
  for(const label of ['rs-quote-edit-draft','rs-quote-preview','打开订单档案','合同.pdf','改善收纳'])assert.ok(html.includes(label),`Missing designer action/content: ${label}`);
  assert.ok(orderHtml.includes('登记收款'),'designer can register a receipt from the order dossier');
  for(const label of ['水电改造','现场图.png','合同金额','应收余额'])assert.ok(orderHtml.includes(label),`Missing designer order content: ${label}`);
  assert.doesNotMatch(html+orderHtml,/rc-cost-new|direct_cost_total|gross_profit|毛利率|采购价/);
});

test('factory purchase uses a wide queue and preserves separate invoices and page attachments',()=>{
  const source=read('factory-cloud.inc.js');
  const start=source.indexOf('  function fcPurchaseFileKey('),end=source.indexOf('  function fcPurchaseReadLines(',start);
  const snippet=source.slice(start,end);let html='';const classes=[],dom={fcPurchaseQueue:{},fcPurchaseContent:{}};
  const ctx={...common,crypto:{randomUUID:()=>`test-${Math.random()}`},fc:{inventory:[],valuation:[]},fcIsOwner:()=>true,fcMoney:common.money,role:'owner',fcToday:()=> '2026-10-16',fcReq:()=> 'req',document:{getElementById:id=>dom[id]||null},fcField:()=>'',fcPurchaseUpdateTotal:()=>{},fcPurchaseRender:()=>{},fcPurchaseRenderQueue:()=>{},fcOrder:()=>({customer_project:'本户客户'}),fcPurchaseRelease:()=>{},openModal:(title,body)=>{html=title+body},$ :()=>({classList:{add:(name)=>classes.push(name)}})};
  vm.runInNewContext(snippet,ctx);ctx.fcPurchaseNew('order');html+=dom.fcPurchaseContent.innerHTML;
  assert.ok(classes.includes('fc-purchase-modal'),'purchase dialog must use the full-width workbench class');
  for(const item of ['fcPurchaseQueue','fcPurchaseContent','multiple','pages','separate','添加另一张单','核对并入库','我已核对本单数量、单位与票面'])assert.ok(html.includes(item),`Missing purchase capability: ${item}`);
  assert.doesNotMatch(html,/订单成本合计/,'purchase invoice should enter inventory and only issue creates order cost');
});

test('factory manager can enter a purchase invoice without seeing a financial summary',()=>{
  const source=read('factory-cloud.inc.js');
  const start=source.indexOf('  function fcPurchaseFileKey('),end=source.indexOf('  function fcPurchaseReadLines(',start);
  const snippet=source.slice(start,end);let html='';const classes=[],dom={fcPurchaseQueue:{},fcPurchaseContent:{}};
  const ctx={...common,crypto:{randomUUID:()=>`test-${Math.random()}`},fc:{inventory:[],valuation:[]},fcIsOwner:()=>false,fcMoney:common.money,role:'factory',fcToday:()=> '2026-10-16',fcReq:()=> 'req',document:{getElementById:id=>dom[id]||null},fcField:()=>'',fcPurchaseUpdateTotal:()=>{},fcPurchaseRender:()=>{},fcPurchaseRenderQueue:()=>{},fcOrder:()=>({customer_project:'本户客户'}),fcPurchaseRelease:()=>{},openModal:(title,body)=>{html=title+body},$ :()=>({classList:{add:(name)=>classes.push(name)}})};
  vm.runInNewContext(snippet,ctx);ctx.fcPurchaseNew('order');html+=dom.fcPurchaseContent.innerHTML;
  assert.ok(classes.includes('fc-purchase-modal'));
  assert.ok(html.includes('核对并入库'));
  assert.ok(html.includes('供应商')&&html.includes('单据号'));
  assert.doesNotMatch(html,/采购单价|票面合计|行金额试算|fcPurchaseTotal|订单成本合计|工资|毛利/);
});

test('multiple file selections append pages without duplicating a queued file',()=>{
  const source=read('factory-cloud.inc.js');
  const start=source.indexOf('  function fcPurchaseFileKey('),end=source.indexOf('  function fcPurchaseNew(',start);
  const snippet=source.slice(start,end);const ctx={};vm.runInNewContext(snippet,ctx);
  const draft={files:[]},a={name:'板材单-1.jpg',size:10,lastModified:1},b={name:'板材单-2.jpg',size:20,lastModified:2};
  assert.equal(ctx.fcPurchaseAttachFiles(draft,[a]).added,1);
  assert.equal(ctx.fcPurchaseAttachFiles(draft,[a,b]).added,1);
  assert.deepEqual(Array.from(draft.files,x=>x.name),[a.name,b.name]);
});

test('factory home puts orders and action items immediately after the statistics',()=>{
  const source=read('factory-cloud.inc.js');
  const start=source.indexOf('  function fcHome(){'),end=source.indexOf('  function fcProduction(){',start);
  const home=source.slice(start,end);
  assert.match(home,/\+fcDashboardOrders\(\)\+fcDashboardTasks\(\)/);
  assert.doesNotMatch(home,/fc-entry-grid/);
});

test('factory progress names are selected and scoped history never exposes actor UUIDs',()=>{
  const source=read('factory-cloud.inc.js');
  assert.match(source,/factory_work_order_history_scoped/);
  assert.match(source,/name="operator_name" required/);
  assert.match(source,/factory_foreman_update_work_order_named/);
  assert.match(source,/operator_name\|\|'系统记录'/);
  assert.match(source,/documentStorageFolder\(invoice\.kind\)/);
});

test('factory finance shows actual cash ledger rows and a registration action',()=>{
  const source=read('factory-cloud.inc.js');
  const start=source.indexOf('  function fcFinance(){'),end=source.indexOf('  function fcDenied()',start);
  const fc={loading:false,loaded:true,financeMonth:'2026-10',accounts:[],fixed:[],orders:[
    {id:'order-1',order_no:'F-1',customer_project:'云端演示户',order_amount:1000,total_cost:200,gross_profit:800,gross_margin:.8,completed_at:null}
  ],cashEntries:[
    {id:'cash-1',order_id:'order-1',order_no:'F-1',customer_project:'云端演示户',entry_kind:'收款',entry_date:'2026-10-03',amount:300,method:'银行转账',counterparty:'客户',note:'定金'},
    {id:'cash-2',order_id:'order-1',order_no:'F-1',customer_project:'云端演示户',entry_kind:'付款',entry_date:'2026-10-04',amount:40,method:'现金',counterparty:'供应商',note:'运费'}
  ],inventory:[]};
  const ctx={...common,fc,fcIsOwner:()=>true,fcMonth:()=> '2026-10',fcDateVal:value=>String(value||'').slice(0,10),fcMoney:common.money,
    fcHead:(en,title,desc,actions='')=>`<h1>${title}</h1>${actions}`,fcBanner:()=>'',fcTable:(heads,rows)=>`<table><thead>${heads.join('|')}</thead><tbody>${rows||''}</tbody></table>`,
    fcOrdersOpts:()=>'<option value="order-1">F-1 · 云端演示户</option>',fcDenied:()=>'<p>denied</p>',
    yjAccountNotice:'账户汇总',yjAccountTable:()=>'<table></table>'};
  vm.runInNewContext(source.slice(start,end),ctx);
  const html=ctx.fcFinance();
  for(const label of ['实际收款、付款与应收','本月实际收款','本月实际付款','本月净现金流','F-1','云端演示户','定金','运费','登记收款 / 付款'])assert.ok(html.includes(label),`Missing factory cash detail: ${label}`);
  assert.ok(html.includes('300'),'current month actual receipts should be calculated from cash entries');
  assert.ok(html.includes('40'),'current month actual payments should be calculated from cash entries');
  assert.ok(html.includes('data-action="fc-cash-new"'),'owner can open the existing cash-entry form from finance');
});
