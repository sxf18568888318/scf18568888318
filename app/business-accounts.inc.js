// Domain: Shared / Overview
// Type: include
// Note: Concatenated into framework-preview.js
// Description: Business accounts and owner overview dashboards.

// Independent business presentation; monetary aggregates come from the database.
const yjAccountLabels={reno:'整装',custom:'定制',factory:'工厂',shared:'共用'};
function yjAccountRows(rows,line,kind='month'){
  return (rows||[]).filter(x=>x.business_line===line&&x.period_kind===kind&&(Number(x.gross_profit)!==0||Number(x.fixed_cost)!==0)).sort((a,b)=>String(a.period).localeCompare(String(b.period)));
}
function yjAccountTable(rows,line,kind='month'){
  const label=yjAccountLabels[line],data=yjAccountRows(rows,line,kind);
  return `<div class="table-wrap"><table><thead><tr><th>${kind==='year'?'年度':'月份'}</th><th>${label}毛利</th><th>${label}固定成本</th><th>${kind==='year'?'年':'月'}净利</th></tr></thead><tbody>${data.map(x=>`<tr><td>${esc(String(x.period).slice(0,kind==='year'?4:7))}</td><td>${money(x.gross_profit)}</td><td>${money(x.fixed_cost)}</td><td><b>${money(x.net_profit)}</b></td></tr>`).join('')||'<tr><td colspan="4" class="empty">暂无本业务结转或固定成本</td></tr>'}</tbody></table></div>`;
}
const yjAccountNotice='本页只列本业务。固定成本按已有归属列示；月薪归工厂固定人工。共用固定成本在经营总览单列，公司合计仅扣一次。';
{
  const overview={loading:false,loaded:false,error:'',accounts:[],monthly:[]};
  async function overviewLoad(){
    if(role!=='owner'||overview.loading)return;
    const c=window.__ANJU_AUTH__?.client;if(!c)return;
    overview.loading=true;overview.error='';
    try{
      const results=await Promise.all([c.schema('api').rpc('owner_business_accounts'),c.schema('api').from('owner_monthly_net_profit').select('*')]);
      for(const r of results)if(r.error)throw r.error;
      overview.accounts=results[0].data||[];overview.monthly=results[1].data||[];overview.loaded=true;
    }catch(e){overview.error=e.message||'读取失败';}finally{overview.loading=false;render();}
  }
  ownerHome=function(){
    if(role!=='owner')return '';
    if(!overview.loaded&&!overview.loading&&!overview.error)queueMicrotask(overviewLoad);
    const month=new Date().toLocaleDateString('sv-SE').slice(0,7),base=overview.monthly.find(x=>String(x.month).slice(0,7)===month),ready=overview.loaded;
    const cards=[['reno','whole/nw-finance'],['custom','custom/custom-finance'],['factory','factory/factory-finance']].map(([line,route])=>{
      const row=overview.accounts.find(x=>x.business_line===line&&x.period_kind==='month'&&String(x.period).slice(0,7)===month);
      return metricLink(`${yjAccountLabels[line]}月净利`,ready?money(row?.net_profit||0):'加载中…',`${month} · ${ready?'完工毛利减本业务固定成本':'正在读取云端台账'}`,'￥',route);
    }).join('');
    const shared=overview.accounts.find(x=>x.business_line==='shared'&&x.period_kind==='month'&&String(x.period).slice(0,7)===month);
    return head('艺匠全屋定制 · 经营总览','三项业务经营总览','各业务独立核算，订单按完工月结转。',`<button class="btn" data-action="yj-overview-refresh">刷新云端数据</button>`)+
      (overview.error?`<div class="callout" role="alert">读取失败：${esc(overview.error)}</div>`:'')+
      `<div class="yj-business-net-cards">${cards}</div>`+
      panel('公司合计',yjAccountNotice,`<div class="cards">${metric('三业务毛利合计',ready?money(base?.gross_total||0):'加载中…','数据库月度汇总','↗')}${metric('共用固定成本',ready?money(shared?.fixed_cost||0):'加载中…','未分配到单一业务的公共费用','￥')}${metric('公司月净利',ready?money(base?.net_profit||0):'加载中…',`${month} · 含全部固定成本`,'￥')}</div>`)+
      `<div class="module-grid ux-three-businesses">${[['whole','整装业务','客户、分部报价、合同、收款与工地'],['custom','全屋定制','柜体报价、材料 BOM、订单与生产交接'],['factory','工厂生产','逐户生产、移动加权库存、考勤与工资']].map(([line,label,note])=>`<button class="module-card" data-route="${line}/home"><h3>${label}</h3><p>${note}</p><span>进入业务 →</span></button>`).join('')}</div>`;
  };
  const overviewAction=action;action=function(name,button){if(name==='yj-overview-refresh'){overview.loaded=false;overviewLoad();return;}return overviewAction(name,button)};
  window.addEventListener('anju:auth-ready',()=>{overview.loaded=false;overview.accounts=[];overview.monthly=[];overview.error='';});
}
{
  let group='全部',search='';
  const groups=['全部','柜类','墙板','五金','其他'];
  function productGroup(p){
    if(['柜体定制','厨房工程'].includes(p.category))return '柜类';
    if(p.category==='墙板与收口')return '墙板';
    if(p.category==='门与五金灯光')return '五金';
    if(p.category==='安装与服务')return '其他';
    if(/墙板|收口|格栅|洞洞板|海棠角|见光板|层板|异形.*桌面|斜边/.test(p.category+' '+p.name))return '墙板';
    if(/五金|铰链|滑轨|拉手|抽轨|灯带|灯光|反弹|挂衣|裤架|拉篮|门与/.test(p.category+' '+p.name))return '五金';
    if(/服务|安装|运输|测量|增项/.test(p.category+' '+p.name))return '其他';
    return '柜类';
  }
  const previousProducts=products;products=function(){
    if(module!=='custom')return previousProducts();
    const items=customProducts.map((p,index)=>({p,index,group:productGroup(p)}));
    const filtered=items.filter(x=>(group==='全部'||x.group===group)&&[x.p.name,x.p.category,x.p.notes,x.p.unit].join(' ').toLowerCase().includes(search.toLowerCase()));
    return head('艺匠 · 定制产品库','柜类 / 墙板 / 五金','按报价产品分类查找；项目名称、单位和计价方式保留原有口径。')+
      `<div class="toolbar"><label class="search">⌕<input id="yjProductSearch" value="${esc(search)}" placeholder="搜索名称、规格或分类"></label><button class="btn" data-action="yj-product-search">搜索</button></div>`+
      `<div class="yj-product-tabs">${groups.map(g=>`<button class="btn ${group===g?'primary':''}" data-action="yj-product-group" data-id="${g}">${g} · ${items.filter(x=>g==='全部'||x.group===g).length}</button>`).join('')}</div>`+
      panel(`${group} · ${filtered.length} 项`,'售价为当前报价参考；不包含采购价或成本。',`<div class="table-wrap"><table><thead><tr><th>产品 / 规格</th><th>分类</th><th>原项目类别</th><th>单位</th><th>计价方式</th><th>客户参考价</th><th>操作</th></tr></thead><tbody>${filtered.map(({p,index,group:g})=>`<tr><td><b>${esc(p.name)}</b><small class="cell-sub">${esc(p.notes||'')}</small></td><td><span class="tag">${g}</span></td><td>${esc(p.category)}</td><td>${esc(p.unit)}</td><td>${esc(p.mode)}</td><td>${p.price?money(p.price):'待核价'}</td><td><button class="btn small" data-action="use-product" data-i="${index}">带入报价 →</button></td></tr>`).join('')||'<tr><td colspan="7" class="empty">没有匹配的项目</td></tr>'}</tbody></table></div>`);
  };
  const productAction=action;action=function(name,b){if(name==='yj-product-group'){group=b.dataset.id;render();return;}if(name==='yj-product-search'){search=$('#yjProductSearch')?.value||'';render();return;}return productAction(name,b)};
  document.addEventListener('keydown',e=>{if(e.target.id==='yjProductSearch'&&e.key==='Enter'){e.preventDefault();search=e.target.value;render();}});
}
