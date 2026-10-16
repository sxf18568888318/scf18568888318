(() => {
  'use strict';

  const PUBLIC_DEMO = document.documentElement.dataset.mode === 'public-demo';
  const KEY = PUBLIC_DEMO ? 'anyang-shared-demo-v1' : 'anyang-renovation-manager-v1';
  const stages = ['线索', '沟通/量房', '报价中', '已签约', '施工/下单', '安装/交付', '售后'];
  const navItems = [
    {id:'home', label:'工作概览', icon:'⌂', roles:['designer','owner']},
    {id:'customers', label:'客户管理', icon:'♙', roles:['designer','owner']},
    {id:'quotes', label:'报价管理', icon:'▤', roles:['designer','owner']},
    {id:'team', label:'团队进度', icon:'◉', roles:['owner']},
    {id:'costs', label:'成本台账', icon:'￥', roles:['owner']},
    {id:'settings', label:'设置与备份', icon:'⚙', roles:['owner']}
  ];
  const defaultDesigners = ['设计师A','设计师B','设计师C'];
  let appState = loadState();
  let role = 'designer';
  let currentDesigner = appState.designers[0] || defaultDesigners[0];
  let currentView = 'home';
  let toastTimer;

  const $ = (selector, root=document) => root.querySelector(selector);
  const $$ = (selector, root=document) => [...root.querySelectorAll(selector)];

  function demoState(){
    const today = new Date();
    const iso = today.toISOString().slice(0,10);
    const ago = new Date(today.getTime()-2*86400000).toISOString().slice(0,10);
    const thisMonth = iso.slice(0,7);
    return {
      version:1,
      designers:[...defaultDesigners],
      customers:[
        {id:'demo-c-1',name:'演示客户甲',phone:'',community:'演示小区一',customerType:'零售',businessType:'全屋定制',designer:'设计师A',stage:'报价中',nextFollowup:iso,notes:'演示样例，可删除或改成实际客户。',followups:[{date:ago,text:'已沟通户型和初步需求'}],isDemo:true,createdAt:ago},
        {id:'demo-c-2',name:'演示客户乙',phone:'',community:'演示小区二',customerType:'渠道',businessType:'整装',designer:'设计师B',stage:'沟通/量房',nextFollowup:iso,notes:'演示样例，可删除或改成实际客户。',followups:[{date:ago,text:'装饰公司转介绍，预约现场沟通'}],isDemo:true,createdAt:ago},
        {id:'demo-c-3',name:'演示客户丙',phone:'',community:'演示小区三',customerType:'零售',businessType:'整装',designer:'设计师C',stage:'已签约',nextFollowup:'',notes:'演示样例，可删除或改成实际客户。',followups:[{date:ago,text:'已确认进入施工交接'}],isDemo:true,createdAt:ago}
      ],
      quotes:[
        {id:'demo-q-1',number:'试用-001',customerId:'demo-c-1',customerName:'演示客户甲',community:'演示小区一',customerType:'零售',businessType:'全屋定制',designer:'设计师A',date:ago,note:'演示报价，仅供查看布局。',items:[{name:'主卧衣柜（演示）',mode:'投影面积',width:2000,height:2400,qty:1,unitPriceFen:73000,unit:'㎡',note:''}],totalFen:350400,isDemo:true},
        {id:'demo-q-2',number:'试用-002',customerId:'demo-c-2',customerName:'演示客户乙',community:'演示小区二',customerType:'渠道',businessType:'整装',designer:'设计师B',date:ago,note:'演示报价，仅供查看流程。',items:[{name:'整装项目（演示）',mode:'手工金额',width:0,height:0,qty:1,unitPriceFen:11200000,unit:'项',note:''}],totalFen:11200000,isDemo:true}
      ],
      costs:[],
      adminPin:''
    };
  }

  function loadState(){
    try{
      const saved=localStorage.getItem(KEY);
      if(saved){
        const parsed=JSON.parse(saved);
        if(parsed && parsed.version===1) return {...demoState(),...parsed};
      }
    }catch(error){console.warn('本地数据读取失败',error);}
    const initial=demoState();
    try{localStorage.setItem(KEY,JSON.stringify(initial));}catch(error){console.warn(error);}
    return initial;
  }

  function persist(){
    try{localStorage.setItem(KEY,JSON.stringify(appState));return true;}
    catch(error){showToast('保存失败：浏览器本地空间不可用，请先导出备份');return false;}
  }

  function uid(prefix='id'){return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,7)}`;}
  function money(fen){return `¥${(Number(fen||0)/100).toLocaleString('zh-CN',{minimumFractionDigits:2,maximumFractionDigits:2})}`;}
  function toFen(yuan){const n=Number(yuan);return Number.isFinite(n)?Math.round(n*100):0;}
  function formatDate(date){if(!date)return '—';return String(date).replaceAll('-','.');}
  function today(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;}
  function currentMonth(){return today().slice(0,7);}
  function escapeHtml(value){return String(value??'').replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));}
  function showToast(message){
    let node=$('.toast');
    if(!node){node=document.createElement('div');node.className='toast';document.body.append(node);}
    node.textContent=message;clearTimeout(toastTimer);toastTimer=setTimeout(()=>node.remove(),2600);
  }
  function statusClass(stage){if(['已签约','安装/交付'].includes(stage))return 'green';if(stage==='报价中')return 'blue';if(stage==='售后')return 'red';return 'amber';}
  function designerCustomers(){return appState.customers.filter(c=>role==='owner'||c.designer===currentDesigner);}
  function designerQuotes(){return appState.quotes.filter(q=>role==='owner'||q.designer===currentDesigner);}

  function render(){
    if(!navItems.some(item=>item.id===currentView&&item.roles.includes(role)))currentView='home';
    renderIdentity();
    renderNav();
    const title=navItems.find(n=>n.id===currentView)?.label||'工作概览';
    $('#pageTitle').textContent=role==='owner'&&currentView==='home'?'老板工作概览':title;
    $('#ownerAccessBtn').classList.toggle('hidden',role==='owner');
    $('#designerAccessBtn').classList.toggle('hidden',role!=='owner');
    $('#ownerBadge').classList.toggle('hidden',role!=='owner');
    $('#designerIdentity').classList.toggle('hidden',role==='owner');
    $('#clearDemoBtn').classList.toggle('hidden',role==='owner'&&currentView==='costs');
    const renderer={home:renderHome,customers:renderCustomers,quotes:renderQuotes,team:renderTeam,costs:renderCosts,settings:renderSettings}[currentView]||renderHome;
    $('#appContent').innerHTML=renderer();
  }

  function renderIdentity(){
    const select=$('#designerSelect');
    select.innerHTML=appState.designers.map(d=>`<option value="${escapeHtml(d)}" ${d===currentDesigner?'selected':''}>${escapeHtml(d)}</option>`).join('');
    if(!appState.designers.includes(currentDesigner))currentDesigner=appState.designers[0]||defaultDesigners[0];
  }

  function renderNav(){
    $('#mainNav').innerHTML=navItems.filter(item=>item.roles.includes(role)).map(item=>`<button class="nav-item ${currentView===item.id?'active':''}" data-nav="${item.id}" type="button"><span class="nav-icon">${item.icon}</span><span>${item.label}</span>${item.id==='customers'?`<span class="nav-count">${designerCustomers().length}</span>`:''}</button>`).join('');
  }

  function renderHome(){
    const clients=designerCustomers();const quotes=designerQuotes();
    const due=clients.filter(c=>c.nextFollowup&&c.nextFollowup<=today()).length;
    const quoteTotal=quotes.reduce((sum,q)=>sum+Number(q.totalFen||0),0);
    const who=role==='owner'?'全团队':currentDesigner;
    const firstCards=role==='owner'?[
      ['客户总数',clients.length,'团队在跟进','♙'],['报价单数',quotes.length,'已保存报价','▤'],['今日待跟进',due,'需要继续联系','◷'],['报价金额',money(quoteTotal),'报价合计，不代表回款','￥']
    ]:[['我的客户',clients.length,'当前负责人：'+currentDesigner,'♙'],['待跟进',due,'到期或已逾期','◷'],['我的报价',quotes.length,'已保存报价','▤'],['报价合计',money(quoteTotal),'不代表实际收款','￥']];
    const recent=clients.filter(c=>c.nextFollowup).sort((a,b)=>a.nextFollowup.localeCompare(b.nextFollowup)).slice(0,4);
    return `<div class="page-head"><div><h2>${role==='owner'?'团队经营概况':`早上好，${escapeHtml(currentDesigner)}`}</h2><p>${role==='owner'?'查看设计师客户进程和报价状态；成本单独进入老板端查看。':'先把客户和报价跟进清楚，下一步就更好安排。'}</p></div><div class="page-actions"><button class="button button-outline" data-action="go-customers">客户管理</button><button class="button button-primary" data-action="new-quote">＋ 新建报价</button></div></div>
      <div class="cards">${firstCards.map(([label,num,sub,icon])=>`<article class="metric-card"><div class="metric-top"><span>${label}</span><span class="metric-emoji">${icon}</span></div><div class="metric-number">${num}</div><div class="metric-sub">${sub}</div></article>`).join('')}</div>
      <div class="split-grid"><section class="panel"><div class="panel-head"><div><h3>${role==='owner'?'团队客户进程':'近期客户跟进'}</h3><p>${role==='owner'?'按当前客户阶段查看团队推进情况':'优先处理今天到期的客户'}</p></div><button class="button button-outline button-small" data-nav="customers">查看客户</button></div>
        <div class="pipeline">${stages.slice(0,6).map(stage=>`<div class="pipeline-chip">${stage}<strong>${clients.filter(c=>c.stage===stage).length}</strong></div>`).join('')}</div>
        ${recent.length?`<div class="followup-list">${recent.map(c=>`<div class="followup-item"><strong>${escapeHtml(c.name)} <span class="tag ${statusClass(c.stage)}">${escapeHtml(c.stage)}</span></strong><p>${escapeHtml(c.community||'未填写小区')} · ${followupStatus(c)} · ${escapeHtml(c.designer)}</p><button class="button button-outline button-small" data-action="followup-customer" data-id="${escapeHtml(c.id)}">记录跟进</button></div>`).join('')}</div>`:`<div class="empty-state"><div class="empty-icon">◷</div><strong>暂时没有待跟进客户</strong><p>在客户资料里设置下次跟进时间后，会显示在这里。</p></div>`}
      </section><section class="panel"><div class="panel-head"><div><h3>最近报价</h3><p>${who} · 最新保存的报价单</p></div><button class="button button-outline button-small" data-nav="quotes">全部报价</button></div>${quotes.length?`<div class="staff-list">${[...quotes].sort((a,b)=>b.date.localeCompare(a.date)).slice(0,4).map(q=>`<div class="staff-row"><div class="staff-avatar">报</div><div class="staff-info"><strong>${escapeHtml(q.customerName||'未命名客户')}</strong><small>${escapeHtml(q.businessType)} · ${escapeHtml(q.number)} · ${formatDate(q.date)}</small></div><div class="amount">${money(q.totalFen)}</div></div>`).join('')}</div>`:`<div class="empty-state"><div class="empty-icon">▤</div><strong>还没有报价</strong><p>创建第一张报价单后，会在这里查看。</p><button class="button button-primary button-small" data-action="new-quote">新建报价</button></div>`}</section></div>
      ${role==='owner'?`<section class="panel"><div class="panel-head"><div><h3>老板专属模块</h3><p>成本台账仅在老板管理端显示，设计师端不会显示成本或工资。</p></div><button class="button button-primary button-small" data-nav="costs">打开成本台账</button></div><div class="permission-note">单机试用版的管理入口用于避免误入，不具备正式账号安全隔离。请先不要在共享电脑中录入需要保密的工资明细。</div></section>`:''}`;
  }

  function followupStatus(c){
    if(!c.nextFollowup)return '<span class="subtle">未安排</span>';
    const date=c.nextFollowup;const label=date<today()?'已逾期':date===today()?'今天跟进':'计划跟进';
    return '<span class="tag '+(date<today()?'red':date===today()?'amber':'green')+'">'+label+'</span> <span class="subtle">'+formatDate(date)+'</span>';
  }
  function openFollowupModal(id){
    const c=designerCustomers().find(x=>x.id===id);if(!c)return;
    modal('记录跟进 · '+c.name,`<form id="followupForm" data-id="${escapeHtml(id)}"><div class="modal-body"><div class="form-grid"><div class="form-field full"><label>本次沟通内容 <span class="required">*</span></label><textarea class="field" name="text" required placeholder="记录客户需求、沟通结果和下一步安排"></textarea></div><div class="form-field"><label>更新客户进程</label><select class="field" name="stage">${stages.map(s=>'<option '+(s===c.stage?'selected':'')+'>'+s+'</option>').join('')}</select></div><div class="form-field"><label>下次跟进日期</label><input class="field" name="nextFollowup" type="date" value="${escapeHtml(c.nextFollowup||'')}"><div class="form-hint">完成本次跟进后，可改约下次日期；留空表示暂不安排。</div></div></div></div><div class="modal-foot"><button type="button" class="button button-outline" data-action="close-modal">取消</button><button class="button button-primary" type="submit">保存跟进</button></div></form>`);
  }
  function saveFollowup(form){
    const c=designerCustomers().find(x=>x.id===form.dataset.id);if(!c)return;
    const data=new FormData(form);const text=String(data.get('text')||'').trim();if(!text){showToast('请填写本次沟通内容');return;}
    c.followups=[...(c.followups||[]),{date:today(),text}];c.stage=String(data.get('stage'));c.nextFollowup=String(data.get('nextFollowup')||'');c.isDemo=false;
    persist();closeModal();render();showToast('跟进已记录');
  }

  function renderCustomers(){
    const clients=designerCustomers();
    return `<div class="page-head"><div><h2>客户管理</h2><p>${role==='owner'?'查看全团队客户进程和跟进安排。':`当前负责人：${escapeHtml(currentDesigner)}。客户资料保存在本机浏览器。`}</p></div><div class="page-actions"><button class="button button-primary" data-action="new-customer">＋ 新建客户</button></div></div>
      <section class="panel"><div class="panel-head"><div><h3>客户列表 <span class="tag">${clients.length} 位</span></h3><p>跟进有记录，报价可回查</p></div><div class="filters"><label class="search-box"><span>⌕</span><input id="customerSearch" placeholder="搜索姓名、小区、电话"></label><select id="customerStageFilter" class="field filter-select"><option value="">全部进程</option>${stages.map(s=>`<option>${s}</option>`).join('')}</select><select id="customerFollowupFilter" class="field filter-select"><option value="">全部跟进安排</option><option value="due">到期及逾期</option><option value="today">今天跟进</option><option value="future">后续跟进</option><option value="unset">未安排跟进</option></select><select id="customerTypeFilter" class="field filter-select"><option value="">全部客户类型</option><option>零售</option><option>渠道</option></select></div></div>
      <div id="customerTable">${customerTable(clients)}</div></section>`;
  }

  function customerTable(clients){
    if(!clients.length)return `<div class="empty-state"><div class="empty-icon">♙</div><strong>还没有客户记录</strong><p>添加一位客户，开始记录需求、跟进和报价进程。</p><button class="button button-primary button-small" data-action="new-customer">＋ 新建客户</button></div>`;
    return `<div class="table-wrap"><table><thead><tr><th>客户 / 小区</th><th>业务类型</th><th>进程</th><th>负责人</th><th>下次跟进</th><th>最近跟进</th><th>操作</th></tr></thead><tbody>${clients.map(c=>`<tr data-customer-row="${escapeHtml(c.id)}"><td><div class="primary-cell">${escapeHtml(c.name)} ${c.isDemo?'<span class="tag amber">演示</span>':''}</div><div class="secondary-cell">${escapeHtml(c.community||'未填写小区')}${c.phone?' · '+escapeHtml(c.phone):''}</div></td><td>${escapeHtml(c.customerType)} · ${escapeHtml(c.businessType)}</td><td><span class="tag ${statusClass(c.stage)}">${escapeHtml(c.stage)}</span></td><td>${escapeHtml(c.designer)}</td><td>${followupStatus(c)}</td><td>${c.followups?.length?escapeHtml(c.followups[c.followups.length-1].text):'<span class="subtle">暂无记录</span>'}</td><td><div class="table-actions"><button class="icon-button" title="记录跟进" data-action="followup-customer" data-id="${escapeHtml(c.id)}">◷</button><button class="icon-button" title="编辑客户" data-action="edit-customer" data-id="${escapeHtml(c.id)}">✎</button><button class="icon-button" title="查看报价" data-action="customer-quotes" data-id="${escapeHtml(c.id)}">▤</button></div></td></tr>`).join('')}</tbody></table></div>`;
  }

  function renderQuotes(){
    const quotes=designerQuotes();
    return `<div class="page-head"><div><h2>报价管理</h2><p>${role==='owner'?'查看团队报价，零售和渠道客户分别标记。':`报价负责人：${escapeHtml(currentDesigner)}。先满足常用尺寸与金额录入。`}</p></div><div class="page-actions"><button class="button button-primary" data-action="new-quote">＋ 新建报价</button></div></div>
      <section class="panel"><div class="panel-head"><div><h3>报价列表 <span class="tag">${quotes.length} 张</span></h3><p>报价金额不等同于已收款金额</p></div><div class="filters"><label class="search-box"><span>⌕</span><input id="quoteSearch" placeholder="搜索客户、小区、报价单号"></label><select id="quoteTypeFilter" class="field filter-select"><option value="">全部业务</option><option>整装</option><option>全屋定制</option></select></div></div><div id="quoteTable">${quoteTable(quotes)}</div></section>`;
  }

  function quoteTable(quotes){
    if(!quotes.length)return `<div class="empty-state"><div class="empty-icon">▤</div><strong>还没有报价</strong><p>新建报价后，可关联客户并打印报价单。</p><button class="button button-primary button-small" data-action="new-quote">＋ 新建报价</button></div>`;
    return `<div class="table-wrap"><table><thead><tr><th>报价单 / 客户</th><th>项目</th><th>类型</th><th>负责人</th><th>日期</th><th>金额</th><th>操作</th></tr></thead><tbody>${[...quotes].sort((a,b)=>b.date.localeCompare(a.date)).map(q=>`<tr><td><div class="primary-cell">${escapeHtml(q.number)} ${q.isDemo?'<span class="tag amber">演示</span>':''}</div><div class="secondary-cell">${escapeHtml(q.customerName||'未关联客户')} · ${escapeHtml(q.community||'')}</div></td><td>${escapeHtml(q.businessType)}</td><td><span class="tag ${q.customerType==='渠道'?'blue':'green'}">${escapeHtml(q.customerType)}</span></td><td>${escapeHtml(q.designer)}</td><td>${formatDate(q.date)}</td><td class="amount">${money(q.totalFen)}</td><td><div class="table-actions"><button class="icon-button" title="报价预览" data-action="preview-quote" data-id="${escapeHtml(q.id)}">▣</button><button class="icon-button" title="复制为新报价" data-action="duplicate-quote" data-id="${escapeHtml(q.id)}">⧉</button><button class="icon-button" title="编辑报价" data-action="edit-quote" data-id="${escapeHtml(q.id)}">✎</button><button class="icon-button" title="删除报价" data-action="delete-quote" data-id="${escapeHtml(q.id)}">×</button></div></td></tr>`).join('')}</tbody></table></div>`;
  }

  function renderTeam(){
    const all=appState.customers;
    const quoteCount=appState.quotes.length;
    return `<div class="page-head"><div><h2>团队进度</h2><p>老板可按设计师查看客户跟进和报价情况。</p></div><div class="page-actions"><button class="button button-outline" data-nav="customers">查看客户</button><button class="button button-primary" data-nav="costs">成本台账</button></div></div>
      <div class="cards"><article class="metric-card"><div class="metric-top">团队客户 <span class="metric-emoji">♙</span></div><div class="metric-number">${all.length}</div><div class="metric-sub">全部设计师</div></article><article class="metric-card"><div class="metric-top">团队报价 <span class="metric-emoji">▤</span></div><div class="metric-number">${quoteCount}</div><div class="metric-sub">报价金额不代表回款</div></article><article class="metric-card"><div class="metric-top">待跟进 <span class="metric-emoji">◷</span></div><div class="metric-number">${all.filter(c=>c.nextFollowup&&c.nextFollowup<=today()).length}</div><div class="metric-sub">到期或已逾期</div></article><article class="metric-card"><div class="metric-top">费用记录 <span class="metric-emoji">￥</span></div><div class="metric-number">${appState.costs.length}</div><div class="metric-sub">老板端手工台账</div></article></div>
      <section class="panel"><div class="panel-head"><div><h3>设计师客户概况</h3><p>客户和报价数据在当前电脑本地保存。</p></div><select id="teamDesignerFilter" class="field filter-select"><option value="">全部设计师</option>${appState.designers.map(d=>`<option>${escapeHtml(d)}</option>`).join('')}</select></div><div id="teamRows">${teamRows('')}</div></section>
      <div class="permission-note">工资、成本和利润模块只在老板端入口显示。当前是单机试用，真实多人权限和跨设备共享需后续部署服务端。</div>`;
  }

  function teamRows(filter){
    const people=filter?[filter]:appState.designers;
    return `<div class="staff-list">${people.map((d,i)=>{const cs=appState.customers.filter(c=>c.designer===d);const qs=appState.quotes.filter(q=>q.designer===d);const due=cs.filter(c=>c.nextFollowup&&c.nextFollowup<=today()).length;const pct=cs.length?Math.max(8,Math.round((cs.filter(c=>['已签约','施工/下单','安装/交付','售后'].includes(c.stage)).length/cs.length)*100)):0;return `<div class="staff-row"><div class="staff-avatar">${escapeHtml(d.slice(-1))}</div><div class="staff-info"><strong>${escapeHtml(d)}</strong><small>${cs.length} 位客户 · ${qs.length} 张报价 · ${due} 位待跟进</small><div class="progress"><span style="width:${pct}%"></span></div></div><div class="staff-count">客户签约/交付阶段<br><strong>${cs.filter(c=>['已签约','施工/下单','安装/交付'].includes(c.stage)).length}</strong></div></div>`;}).join('')}</div>`;
  }

  function renderCosts(){
    const month=$('#costMonth')?.value||currentMonth();
    const costs=appState.costs.filter(c=>(c.date||'').slice(0,7)===month).sort((a,b)=>b.date.localeCompare(a.date));
    const total=costs.reduce((n,c)=>n+Number(c.amountFen||0),0);
    const categories=['房租','水电','工资','日常运营','材料','加工','安装','运输','其他'];
    const sums=categories.map(category=>[category,costs.filter(c=>c.category===category).reduce((n,c)=>n+Number(c.amountFen||0),0)]).filter(x=>x[1]>0);
    return `<div class="page-head"><div><h2>成本台账</h2><p>老板手动登记当月费用；第一版只汇总费用，不自动计算毛利或净利润。</p></div><div class="page-actions"><button class="button button-primary" data-action="new-cost">＋ 添加成本</button></div></div>
      <div class="permission-note">此处可手动记录房租、水电、工资等管理费用。设计师工作台不会显示本模块。单机试用密码只避免误入，不是正式安全权限。</div>
      <div class="cards"><article class="metric-card"><div class="metric-top">${month} 费用合计 <span class="metric-emoji">￥</span></div><div class="metric-number">${money(total)}</div><div class="metric-sub">根据已登记的成本记录统计</div></article><article class="metric-card"><div class="metric-top">本月记录 <span class="metric-emoji">▤</span></div><div class="metric-number">${costs.length}</div><div class="metric-sub">可按类别筛选和维护</div></article></div>
      <section class="panel"><div class="panel-head"><div><h3>月度成本明细</h3><p>手工录入，实际金额以票据和付款记录为准。</p></div><div class="filters"><input id="costMonth" class="field filter-select" type="month" value="${month}"><button class="button button-outline button-small" data-action="export-costs">导出 CSV</button></div></div>
      ${sums.length?`<div class="pipeline">${sums.map(([c,v])=>`<div class="pipeline-chip">${escapeHtml(c)}<strong>${money(v)}</strong></div>`).join('')}</div>`:''}
      <div id="costTable">${costTable(costs)}</div></section>`;
  }

  function costTable(costs){
    if(!costs.length)return `<div class="empty-state"><div class="empty-icon">￥</div><strong>这个月还没有成本记录</strong><p>先手动登记房租、水电或日常运营费用。</p><button class="button button-primary button-small" data-action="new-cost">＋ 添加成本</button></div>`;
    return `<div class="table-wrap"><table><thead><tr><th>日期</th><th>类别</th><th>项目</th><th>备注</th><th>金额</th><th>操作</th></tr></thead><tbody>${costs.map(c=>`<tr><td>${formatDate(c.date)}</td><td><span class="tag cost-category">${escapeHtml(c.category)}</span></td><td class="primary-cell">${escapeHtml(c.title)}</td><td>${escapeHtml(c.note||'—')}</td><td class="amount">${money(c.amountFen)}</td><td><div class="table-actions"><button class="icon-button" data-action="edit-cost" data-id="${escapeHtml(c.id)}" title="编辑">✎</button><button class="icon-button" data-action="delete-cost" data-id="${escapeHtml(c.id)}" title="删除">×</button></div></td></tr>`).join('')}</tbody></table></div>`;
  }

  function renderSettings(){
    return `<div class="page-head"><div><h2>设置与备份</h2><p>维护试用设计师名单，导出本机数据备份。</p></div></div><section class="panel"><div class="panel-head"><div><h3>设计师名单</h3><p>仅影响本机试用身份筛选。</p></div></div><form id="designerSettingsForm"><div class="form-field"><label>设计师姓名（用中文逗号或英文逗号分开）</label><input class="field" name="designers" value="${escapeHtml(appState.designers.join('，'))}" required></div><div class="page-actions" style="margin-top:12px"><button class="button button-primary" type="submit">保存名单</button></div></form></section>
      <section class="panel"><div class="panel-head"><div><h3>数据备份</h3><p>备份包含客户、报价、跟进记录和成本台账，请妥善保管。</p></div></div><div class="page-actions"><button class="button button-outline" data-action="backup-export">导出 JSON 备份</button><button class="button button-outline" data-action="backup-import">从 JSON 恢复</button><button class="button button-danger" data-action="reset-pin">重设本地管理密码</button></div><p class="hint-text" style="margin-top:12px">备份文件含有老板端成本信息，只应由管理人员保管。当前密码用于本机界面入口，不是正式账号权限。</p></section>`;
  }

  function modal(title,body,options={}){
    const root=$('#dialogRoot');
    root.innerHTML=`<div class="modal-backdrop" data-backdrop><section class="modal ${options.narrow?'narrow':''}" role="dialog" aria-modal="true"><div class="modal-head"><h3>${title}</h3><button class="modal-close" data-action="close-modal" aria-label="关闭">×</button></div>${body}</section></div>`;
  }
  function closeModal(){$('#dialogRoot').innerHTML='';}

  function openPinModal(setup=false){
    const body=`<form id="pinForm" data-mode="${setup?'setup':'login'}"><div class="modal-body"><div class="permission-note">老板端包含成本台账。此本地试用密码只用于页面入口，不提供正式安全隔离。</div>${setup?`<div class="form-field"><label>设置老板端本地密码（4–12 位）</label><input class="field" type="password" name="pin" inputmode="numeric" minlength="4" maxlength="12" required></div><div class="form-field" style="margin-top:12px"><label>再次输入</label><input class="field" type="password" name="confirm" inputmode="numeric" minlength="4" maxlength="12" required></div>`:`<div class="form-field"><label>输入老板端本地密码</label><input class="field" type="password" name="pin" inputmode="numeric" required autofocus></div>`}</div><div class="modal-foot"><button class="button button-outline" type="button" data-action="close-modal">取消</button><button class="button button-primary" type="submit">${setup?'设置并进入':'进入老板端'}</button></div></form>`;
    modal(setup?'首次设置老板入口':'老板管理端验证',body,{narrow:true});
  }

  function openCustomerModal(customer=null){
    const editing=Boolean(customer);const c=customer||{name:'',phone:'',community:'',customerType:'零售',businessType:'全屋定制',designer:role==='designer'?currentDesigner:appState.designers[0],stage:'线索',nextFollowup:'',notes:'',followups:[]};
    const staffOptions=appState.designers.map(d=>`<option ${d===c.designer?'selected':''}>${escapeHtml(d)}</option>`).join('');
    const followups=(c.followups||[]).slice().reverse().map(f=>`<div class="mini-stat"><span>${formatDate(f.date)} · ${escapeHtml(f.text)}</span></div>`).join('');
    const body=`<form id="customerForm" data-id="${editing?escapeHtml(c.id):''}"><div class="modal-body"><div class="form-grid">
      <div class="form-field"><label>客户姓名 <span class="required">*</span></label><input class="field" name="name" value="${escapeHtml(c.name)}" required></div>
      <div class="form-field"><label>联系电话</label><input class="field" name="phone" value="${escapeHtml(c.phone||'')}" inputmode="tel"></div>
      <div class="form-field"><label>小区 / 项目</label><input class="field" name="community" value="${escapeHtml(c.community||'')}"></div>
      <div class="form-field"><label>负责人</label><select class="field" name="designer" ${role==='designer'?'disabled':''}>${staffOptions}</select>${role==='designer'?`<input type="hidden" name="designer" value="${escapeHtml(currentDesigner)}">`:''}</div>
      <div class="form-field"><label>客户类型</label><select class="field" name="customerType"><option ${c.customerType==='零售'?'selected':''}>零售</option><option ${c.customerType==='渠道'?'selected':''}>渠道</option></select></div>
      <div class="form-field"><label>业务方向</label><select class="field" name="businessType"><option ${c.businessType==='全屋定制'?'selected':''}>全屋定制</option><option ${c.businessType==='整装'?'selected':''}>整装</option></select></div>
      <div class="form-field"><label>客户阶段</label><select class="field" name="stage">${stages.map(s=>`<option ${s===c.stage?'selected':''}>${s}</option>`).join('')}</select></div>
      <div class="form-field"><label>下次跟进时间</label><input class="field" name="nextFollowup" type="date" value="${escapeHtml(c.nextFollowup||'')}"></div>
      <div class="form-field full"><label>本次跟进记录</label><input class="field" name="followupText" placeholder="例如：电话沟通了户型和大致需求"></div>
      <div class="form-field full"><label>客户备注</label><textarea class="field" name="notes">${escapeHtml(c.notes||'')}</textarea></div>
      ${followups?`<div class="form-field full"><label>历史跟进</label>${followups}</div>`:''}
      </div></div><div class="modal-foot"><button class="button button-outline" type="button" data-action="close-modal">取消</button>${editing?`<button class="button button-danger" type="button" data-action="delete-customer" data-id="${escapeHtml(c.id)}">删除</button>`:''}<button class="button button-primary" type="submit">保存客户</button></div></form>`;
    modal(editing?'编辑客户':'新建客户',body);
  }

  function openCostModal(cost=null){
    const editing=Boolean(cost);const c=cost||{date:today(),category:'日常运营',title:'',amountFen:0,note:''};
    const cats=['房租','水电','工资','日常运营','材料','加工','安装','运输','其他'];
    modal(editing?'编辑成本记录':'添加成本记录',`<form id="costForm" data-id="${editing?escapeHtml(c.id):''}"><div class="modal-body"><div class="form-grid"><div class="form-field"><label>日期</label><input class="field" name="date" type="date" value="${escapeHtml(c.date)}" required></div><div class="form-field"><label>类别</label><select class="field" name="category">${cats.map(v=>`<option ${v===c.category?'selected':''}>${v}</option>`).join('')}</select></div><div class="form-field"><label>项目名称 <span class="required">*</span></label><input class="field" name="title" value="${escapeHtml(c.title)}" placeholder="例如：10月门店房租" required></div><div class="form-field"><label>金额（元） <span class="required">*</span></label><input class="field" name="amount" type="number" min="0" step="0.01" value="${Number(c.amountFen||0)/100}" required></div><div class="form-field full"><label>备注</label><textarea class="field" name="note">${escapeHtml(c.note||'')}</textarea></div></div></div><div class="modal-foot"><button class="button button-outline" type="button" data-action="close-modal">取消</button><button class="button button-primary" type="submit">保存记录</button></div></form>`);
  }

  function quoteLineHtml(item={}){
    const mode=item.mode||'投影面积';
    return `<div class="quote-line" data-quote-line><input data-name placeholder="项目名称" value="${escapeHtml(item.name||'')}" aria-label="项目名称"><select data-mode aria-label="计价方式"><option ${mode==='投影面积'?'selected':''}>投影面积</option><option ${mode==='延米'?'selected':''}>延米</option><option ${mode==='按件/套'?'selected':''}>按件/套</option><option ${mode==='手工金额'?'selected':''}>手工金额</option></select><input data-width type="number" min="0" placeholder="宽/长 mm" value="${item.width||''}" aria-label="宽或长度毫米"><input data-height type="number" min="0" placeholder="高 mm" value="${item.height||''}" aria-label="高毫米"><input data-qty type="number" min="0" step="0.01" value="${item.qty??1}" aria-label="数量"><input data-price type="number" min="0" step="0.01" value="${Number(item.unitPriceFen||0)/100}" placeholder="单价" aria-label="单价元"><span class="line-amount amount">¥0.00</span><button type="button" class="icon-button" data-remove-line title="删除项目">×</button></div>`;
  }

  function calcQuoteLine(row){
    const mode=$('[data-mode]',row).value;
    const width=Number($('[data-width]',row).value)||0;
    const height=Number($('[data-height]',row).value)||0;
    const qty=Number($('[data-qty]',row).value)||0;
    const priceFen=toFen($('[data-price]',row).value);
    let quantity=qty;let unit='项';
    if(mode==='投影面积'){quantity=width*height*qty/1000000;unit='㎡';}
    else if(mode==='延米'){quantity=width*qty/1000;unit='米';}
    else if(mode==='按件/套'){unit='件/套';}
    else {unit='项';}
    const amountFen=mode==='手工金额'?priceFen:Math.round(quantity*priceFen);
    const amount=$('.line-amount',row);if(amount)amount.textContent=money(amountFen);
    return {mode,width,height,qty,priceFen,quantity,unit,amountFen};
  }

  function openQuoteModal(quote=null, preselectedCustomerId=''){
    const editing=Boolean(quote?.id);const customers=designerCustomers();
    const q=quote||{customerId:preselectedCustomerId,customerType:'零售',businessType:'全屋定制',designer:role==='designer'?currentDesigner:appState.designers[0],date:today(),note:'',items:[{name:'',mode:'投影面积',qty:1,width:0,height:0,unitPriceFen:0}]};
    const customerOptions=[`<option value="">暂不关联客户</option>`,...customers.map(c=>`<option value="${escapeHtml(c.id)}" ${c.id===q.customerId?'selected':''}>${escapeHtml(c.name)} · ${escapeHtml(c.community||'未填小区')}</option>`)].join('');
    const body=`<form id="quoteForm" data-id="${editing?escapeHtml(q.id):''}"><div class="modal-body"><div class="form-grid">
      <div class="form-field"><label>关联客户</label><select class="field" name="customerId">${customerOptions}</select></div><div class="form-field"><label>报价日期</label><input class="field" name="date" type="date" value="${escapeHtml(q.date||today())}" required></div>
      <div class="form-field"><label>客户姓名</label><input class="field" name="customerName" value="${escapeHtml(q.customerName||customers.find(c=>c.id===q.customerId)?.name||'')}" placeholder="关联客户后自动填入，也可手工填写" required></div><div class="form-field"><label>小区 / 项目</label><input class="field" name="community" value="${escapeHtml(q.community||customers.find(c=>c.id===q.customerId)?.community||'')}" placeholder="项目地址或小区名称"></div>
      <div class="form-field"><label>客户类型</label><select class="field" name="customerType"><option ${q.customerType==='零售'?'selected':''}>零售</option><option ${q.customerType==='渠道'?'selected':''}>渠道</option></select></div><div class="form-field"><label>业务类型</label><select class="field" name="businessType"><option ${q.businessType==='全屋定制'?'selected':''}>全屋定制</option><option ${q.businessType==='整装'?'selected':''}>整装</option></select></div>
      <div class="form-field"><label>负责人</label><select class="field" name="designer" ${role==='designer'?'disabled':''}>${appState.designers.map(d=>`<option ${d===q.designer?'selected':''}>${escapeHtml(d)}</option>`).join('')}</select>${role==='designer'?`<input type="hidden" name="designer" value="${escapeHtml(currentDesigner)}">`:''}</div>
      <div class="form-field"><label>颜色 / 工艺备注</label><input class="field" name="note" value="${escapeHtml(q.note||'')}" placeholder="颜色、工艺或特别说明"></div>
      <div class="form-field full"><div class="panel-head"><div><h3>报价项目</h3><p>投影面积按宽 × 高 × 数量；金额按元录入。</p></div><button class="button button-outline button-small" type="button" data-action="add-quote-line">＋ 添加项目</button></div><div class="quote-lines"><div class="quote-line line-head"><span>项目名称</span><span>计价方式</span><span>宽/长</span><span>高</span><span>数量</span><span>单价（元）</span><span>金额</span><span></span></div><div id="quoteLines">${(q.items||[]).map(item=>quoteLineHtml(item)).join('')}</div></div><div class="quote-total"><span>报价合计</span><strong id="quoteTotal">¥0.00</strong><span class="total-note">实际成交以双方确认合同为准</span></div></div>
      </div></div><div class="modal-foot"><button class="button button-outline" type="button" data-action="close-modal">取消</button><button class="button button-primary" type="submit">保存报价</button></div></form>`;
    modal(editing?'编辑报价':'新建报价',body);
    recalcQuoteModal();
  }

  function recalcQuoteModal(){
    const rows=$$('[data-quote-line]');let total=0;rows.forEach(row=>total+=calcQuoteLine(row).amountFen);const totalEl=$('#quoteTotal');if(totalEl)totalEl.textContent=money(total);
  }

  function getQuoteLines(){
    return $$('[data-quote-line]').map(row=>{const calc=calcQuoteLine(row);return {name:$('[data-name]',row).value.trim(),mode:calc.mode,width:calc.width,height:calc.height,qty:calc.qty,quantity:calc.quantity,unitPriceFen:calc.priceFen,unit:calc.unit,amountFen:calc.amountFen,note:''};}).filter(item=>item.name||item.amountFen>0);
  }

  function saveCustomer(form){
    const fd=new FormData(form);const id=form.dataset.id;const old=id?appState.customers.find(c=>c.id===id):null;
    const followups=[...(old?.followups||[])];const note=String(fd.get('followupText')||'').trim();if(note)followups.push({date:today(),text:note});
    const entry={...(old||{}),id:id||uid('c'),name:String(fd.get('name')||'').trim(),phone:String(fd.get('phone')||'').trim(),community:String(fd.get('community')||'').trim(),designer:String(fd.get('designer')||currentDesigner),customerType:String(fd.get('customerType')||'零售'),businessType:String(fd.get('businessType')||'全屋定制'),stage:String(fd.get('stage')||'线索'),nextFollowup:String(fd.get('nextFollowup')||''),notes:String(fd.get('notes')||'').trim(),followups,isDemo:false,createdAt:old?.createdAt||today()};
    if(old)appState.customers=appState.customers.map(c=>c.id===id?entry:c);else appState.customers.unshift(entry);
    persist();closeModal();render();showToast(old?'客户资料已更新':'客户已保存');
  }

  function saveQuote(form){
    const fd=new FormData(form);const id=form.dataset.id;const old=id?appState.quotes.find(q=>q.id===id):null;
    const customer=appState.customers.find(c=>c.id===fd.get('customerId'));
    const items=getQuoteLines();if(!items.length){showToast('请至少添加一个有名称或金额的报价项目');return;}
    const totalFen=items.reduce((s,i)=>s+i.amountFen,0);
    if(!old)appState.quoteSequence=(Number(appState.quoteSequence)||appState.quotes.length)+1;
    const entry={...(old||{}),id:id||uid('q'),number:old?.number||`Q-${today().replaceAll('-','')}-${String(appState.quoteSequence).padStart(3,'0')}`,customerId:customer?.id||'',customerName:String(fd.get('customerName')||customer?.name||old?.customerName||'未关联客户').trim(),community:String(fd.get('community')||customer?.community||old?.community||'').trim(),phone:customer?.phone||old?.phone||'',customerType:String(fd.get('customerType')||'零售'),businessType:String(fd.get('businessType')||'全屋定制'),designer:String(fd.get('designer')||currentDesigner),date:String(fd.get('date')||today()),note:String(fd.get('note')||'').trim(),items,totalFen,isDemo:false};
    if(old)appState.quotes=appState.quotes.map(q=>q.id===id?entry:q);else appState.quotes.unshift(entry);
    persist();closeModal();currentView='quotes';render();showToast(old?'报价已更新':'报价已保存');
  }

  function saveCost(form){
    const fd=new FormData(form);const id=form.dataset.id;const old=id?appState.costs.find(c=>c.id===id):null;
    const entry={...(old||{}),id:id||uid('cost'),date:String(fd.get('date')||today()),category:String(fd.get('category')||'其他'),title:String(fd.get('title')||'').trim(),amountFen:toFen(fd.get('amount')),note:String(fd.get('note')||'').trim()};
    if(entry.amountFen<0){showToast('金额不能小于 0');return;}
    if(old)appState.costs=appState.costs.map(c=>c.id===id?entry:c);else appState.costs.unshift(entry);
    persist();closeModal();render();showToast(old?'成本记录已更新':'成本记录已保存');
  }

  function quoteMarkup(q){
    const itemRows=(q.items||[]).map((item,i)=>{
      let quantity=Number(item.qty)||0;
      if(item.mode==='投影面积')quantity=(Number(item.width)||0)*(Number(item.height)||0)*quantity/1000000;
      if(item.mode==='延米')quantity=(Number(item.width)||0)*quantity/1000;
      const amount=item.mode==='手工金额'?Number(item.unitPriceFen||0):Math.round(quantity*Number(item.unitPriceFen||0));
      const specification=item.width||item.height?`${item.width||'—'} × ${item.height||'—'}`:'—';
      return `<tr><td>${i+1}</td><td>${escapeHtml(item.name)}</td><td>${escapeHtml(specification)}</td><td>${Number(quantity.toFixed(4))} ${escapeHtml(item.unit)}</td><td>${money(item.unitPriceFen)}</td><td>${money(amount)}</td></tr>`;
    }).join('');
    return `<div class="print-page"><h1>整装 · 全屋定制报价单</h1><div class="print-sub">客户报价预览 · 请以双方签字确认内容为准</div><div class="print-meta"><span>客户：${escapeHtml(q.customerName)}</span><span>小区/项目：${escapeHtml(q.community||'—')}</span><span>联系电话：${escapeHtml(q.phone||appState.customers.find(c=>c.id===q.customerId)?.phone||'—')}</span><span>报价单号：${escapeHtml(q.number)}</span><span>业务类型：${escapeHtml(q.businessType)}</span><span>客户类型：${escapeHtml(q.customerType)}</span><span>设计师：${escapeHtml(q.designer)}</span><span>日期：${formatDate(q.date)}</span></div><div class="table-wrap"><table><thead><tr><th>序号</th><th>项目名称</th><th>规格（mm）</th><th>数量/面积</th><th>单价</th><th>金额</th></tr></thead><tbody>${itemRows}</tbody></table></div><div class="print-total">报价合计：${money(q.totalFen)}</div><div>颜色 / 工艺备注：${escapeHtml(q.note||'无')}</div><div class="print-note">报价有效期及正式合同条款以双方确认内容为准。此报价单由试用版生成。</div></div>`;
  }
  function previewQuote(id){const q=appState.quotes.find(x=>x.id===id);if(!q)return;modal('报价预览',`<div class="modal-body quote-preview-body">${quoteMarkup(q)}</div><div class="modal-foot"><button class="button button-outline" data-action="close-modal">关闭</button><button class="button button-primary" data-action="print-quote" data-id="${escapeHtml(id)}">打印 / 保存 PDF</button></div>`);}
  function printQuote(id){
    const q=appState.quotes.find(x=>x.id===id);if(!q)return;
    let root=$('#printRoot');if(!root){root=document.createElement('div');root.id='printRoot';document.body.append(root);}
    root.innerHTML=quoteMarkup(q);document.body.classList.add('printing');
    const cleanup=()=>{document.body.classList.remove('printing');root.innerHTML='';};
    window.addEventListener('afterprint',cleanup,{once:true});setTimeout(()=>window.print(),80);
  }

  function openBackupExport(){
    const blob=new Blob([JSON.stringify({...appState,exportedAt:new Date().toISOString()},null,2)],{type:'application/json'});
    const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`整装定制试用备份-${today()}.json`;a.click();URL.revokeObjectURL(a.href);showToast('备份文件已导出，请由老板妥善保管');
  }

  function openImportPicker(){$('#backupFile').click();}

  function openQuoteCustomer(id){currentView='quotes';render();const search=$('#quoteSearch');if(search){const c=appState.customers.find(x=>x.id===id);search.value=c?.name||'';filterQuotes();}}
  function filterCustomers(){
    const query=($('#customerSearch')?.value||'').trim().toLowerCase();const stage=$('#customerStageFilter')?.value||'';const type=$('#customerTypeFilter')?.value||'';const followup=$('#customerFollowupFilter')?.value||'';
    const rows=designerCustomers().filter(c=>(!query||[c.name,c.community,c.phone].join(' ').toLowerCase().includes(query))&&(!stage||c.stage===stage)&&(!type||c.customerType===type)&&(!followup||(followup==='due'&&c.nextFollowup&&c.nextFollowup<=today())||(followup==='today'&&c.nextFollowup===today())||(followup==='future'&&c.nextFollowup>today())||(followup==='unset'&&!c.nextFollowup))).sort((a,b)=>(a.nextFollowup||'9999').localeCompare(b.nextFollowup||'9999'));
    $('#customerTable').innerHTML=customerTable(rows);
  }
  function filterQuotes(){
    const query=($('#quoteSearch')?.value||'').trim().toLowerCase();const business=$('#quoteTypeFilter')?.value||'';
    const rows=designerQuotes().filter(q=>(!query||[q.customerName,q.community,q.number].join(' ').toLowerCase().includes(query))&&(!business||q.businessType===business));
    $('#quoteTable').innerHTML=quoteTable(rows);
  }

  document.addEventListener('click',event=>{
    const remove=event.target.closest('[data-remove-line]');if(remove){remove.closest('[data-quote-line]').remove();recalcQuoteModal();return;}
    const button=event.target.closest('[data-nav],[data-action]');if(!button)return;
    if(button.dataset.nav){currentView=button.dataset.nav;render();return;}
    const action=button.dataset.action;const id=button.dataset.id;
    switch(action){
      case 'close-modal':closeModal();break;
      case 'new-customer':openCustomerModal();break;
      case 'followup-customer':openFollowupModal(id);break;
      case 'edit-customer':{const c=appState.customers.find(x=>x.id===id);if(c)openCustomerModal(c);break;}
      case 'delete-customer':if(confirm('确定删除这位客户吗？已保存的报价单仍会保留报价快照。')){appState.customers=appState.customers.filter(c=>c.id!==id);persist();closeModal();render();showToast('客户已删除');}break;
      case 'customer-quotes':openQuoteCustomer(id);break;
      case 'new-quote':openQuoteModal();break;
      case 'duplicate-quote':{const q=designerQuotes().find(x=>x.id===id);if(q){openQuoteModal({...q,id:'',number:'',date:today(),items:q.items.map(i=>({...i})),isDemo:false});showToast('已复制项目，请确认客户、尺寸和价格后保存');}break;}
      case 'edit-quote':{const q=appState.quotes.find(x=>x.id===id);if(q)openQuoteModal(q);break;}
      case 'delete-quote':if(confirm('确定删除这张报价吗？')){appState.quotes=appState.quotes.filter(q=>q.id!==id);persist();render();showToast('报价已删除');}break;
      case 'print-quote':printQuote(id);break;
      case 'preview-quote':previewQuote(id);break;
      case 'add-quote-line':$('#quoteLines')?.insertAdjacentHTML('beforeend',quoteLineHtml());recalcQuoteModal();break;
      case 'new-cost':if(role==='owner')openCostModal();break;
      case 'edit-cost':{const c=appState.costs.find(x=>x.id===id);if(c&&role==='owner')openCostModal(c);break;}
      case 'delete-cost':if(role==='owner'&&confirm('确定删除这条成本记录吗？')){appState.costs=appState.costs.filter(c=>c.id!==id);persist();render();showToast('成本记录已删除');}break;
      case 'backup-export':if(role==='owner')openBackupExport();break;
      case 'backup-import':if(role==='owner')openImportPicker();break;
      case 'reset-pin':if(role==='owner'&&confirm('重设后将需要重新设置老板端本地密码。继续吗？')){appState.adminPin='';persist();showToast('本地密码已清除');}break;
      case 'export-costs':if(role==='owner')exportCostsCsv();break;
      case 'go-customers':currentView='customers';render();break;
      default:break;
    }
  });

  document.addEventListener('input',event=>{
    if(event.target.closest('#quoteLines'))recalcQuoteModal();
    if(event.target.id==='customerSearch'||event.target.id==='customerStageFilter'||event.target.id==='customerTypeFilter'||event.target.id==='customerFollowupFilter')filterCustomers();
    if(event.target.id==='quoteSearch'||event.target.id==='quoteTypeFilter')filterQuotes();
  });
  document.addEventListener('change',event=>{
    if(event.target.closest('#quoteLines'))recalcQuoteModal();
    if(event.target.matches('#quoteForm [name="customerId"]')){const c=appState.customers.find(x=>x.id===event.target.value);if(c){const f=$('#quoteForm');f.elements.customerName.value=c.name;f.elements.community.value=c.community||'';f.elements.customerType.value=c.customerType;f.elements.businessType.value=c.businessType;}}
    if(event.target.id==='designerSelect'){currentDesigner=event.target.value;render();}
    if(event.target.id==='customerStageFilter'||event.target.id==='customerTypeFilter'||event.target.id==='customerFollowupFilter')filterCustomers();
    if(event.target.id==='quoteTypeFilter')filterQuotes();
    if(event.target.id==='costMonth')render();
    if(event.target.id==='teamDesignerFilter')$('#teamRows').innerHTML=teamRows(event.target.value);
  });

  document.addEventListener('submit',event=>{
    const form=event.target;
    if(form.getAttribute('id')==='pinForm'){
      event.preventDefault();const fd=new FormData(form);const pin=String(fd.get('pin')||'');
      if(form.dataset.mode==='setup'){
        if(pin.length<4||pin.length>12){showToast('密码长度请设置为 4–12 位');return;}
        if(pin!==String(fd.get('confirm')||'')){showToast('两次输入的密码不一致');return;}
        appState.adminPin=pin;persist();role='owner';currentView='home';closeModal();render();showToast('老板管理端已开启');
      }else if(pin===appState.adminPin){role='owner';currentView='home';closeModal();render();showToast('已进入老板管理端');}
      else showToast('密码不正确');
      return;
    }
    if(form.getAttribute('id')==='followupForm'){event.preventDefault();saveFollowup(form);return;}
    if(form.getAttribute('id')==='customerForm'){event.preventDefault();saveCustomer(form);return;}
    if(form.getAttribute('id')==='quoteForm'){event.preventDefault();saveQuote(form);return;}
    if(form.getAttribute('id')==='costForm'){event.preventDefault();saveCost(form);return;}
    if(form.getAttribute('id')==='designerSettingsForm'){
      event.preventDefault();const values=String(new FormData(form).get('designers')||'').split(/[,，、]/).map(v=>v.trim()).filter(Boolean);
      if(!values.length){showToast('请至少保留一名设计师');return;}
      appState.designers=[...new Set(values)];if(!appState.designers.includes(currentDesigner))currentDesigner=appState.designers[0];
      persist();render();showToast('设计师名单已保存');return;
    }
  });

  $('#ownerAccessBtn').addEventListener('click',()=>{if(PUBLIC_DEMO){role='owner';currentView='home';render();}else openPinModal(!appState.adminPin);});
  $('#designerAccessBtn').addEventListener('click',()=>{role='designer';currentView='home';render();});
  $('#clearDemoBtn').addEventListener('click',()=>{
    const demos=appState.customers.filter(c=>c.isDemo).length+appState.quotes.filter(q=>q.isDemo).length;
    if(!demos){showToast('没有演示样例需要清理');return;}
    if(!confirm('清除所有标记为“演示”的客户和报价吗？自己录入的数据不会删除。'))return;
    const ids=new Set(appState.customers.filter(c=>c.isDemo).map(c=>c.id));
    appState.customers=appState.customers.filter(c=>!c.isDemo);appState.quotes=appState.quotes.filter(q=>!q.isDemo);persist();render();showToast('演示样例已清除');
  });
  $('#backupFile').addEventListener('change',async event=>{
    const file=event.target.files?.[0];if(!file)return;
    try{const parsed=JSON.parse(await file.text());if(parsed.version!==1||!Array.isArray(parsed.customers)||!Array.isArray(parsed.quotes)||!Array.isArray(parsed.costs))throw new Error('文件格式不正确');if(!confirm('恢复备份会覆盖当前浏览器里的所有客户、报价和成本记录。确定继续吗？'))return;appState={...parsed,designers:Array.isArray(parsed.designers)&&parsed.designers.length?parsed.designers:defaultDesigners};persist();currentDesigner=appState.designers[0];currentView='home';role='designer';render();showToast('数据备份已恢复');}
    catch(error){showToast(`恢复失败：${error.message||'文件无法读取'}`);}finally{event.target.value='';}
  });

  function exportCostsCsv(){
    const rows=[['日期','类别','项目','金额（元）','备注'],...appState.costs.map(c=>[c.date,c.category,c.title,(c.amountFen/100).toFixed(2),c.note||''])];
    const csv='\ufeff'+rows.map(row=>row.map(cell=>`"${String(cell).replaceAll('"','""')}"`).join(',')).join('\r\n');
    const blob=new Blob([csv],{type:'text/csv;charset=utf-8'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=`成本台账-${currentMonth()}.csv`;a.click();URL.revokeObjectURL(a.href);showToast('成本台账 CSV 已导出');
  }

  function init(){
    if(!appState.designers.length)appState.designers=[...defaultDesigners];
    if(!appState.designers.includes(currentDesigner))currentDesigner=appState.designers[0];
    render();
  }
  init();
})();
