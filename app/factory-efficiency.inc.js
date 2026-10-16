  // Practical factory coordination: readiness, due dates, blockers and reusable offcuts.
  for (const key of ['blockers','offcuts','offcutMoves']) {
    if (!Array.isArray(foState[key])) foState[key] = [];
  }
  const feChecklist = [
    ['quote','接单金额与范围'], ['drawing','尺寸 / 图纸已确认'],
    ['board','柜体 / 柜门配置'], ['hardware','五金及升级约定'], ['requirements','特殊工艺 / 外协要求']
  ];
  let feOffcutSearch='';
  const feActive = () => factoryJobRecords.filter(j => j.status !== '出货完成');
  const feOpenBlockers = id => foState.blockers.filter(b => !b.resolved && (!id || b.orderId === id));
  function feMissing(j) {
    const missing = feChecklist.filter(([key]) => !j.handoff?.[key]).map(([,label]) => label);
    if (!j.dueDate) missing.push('约定交货日期');
    if (!j.responsible) missing.push('生产负责人');
    return missing;
  }
  function feDue(j) {
    if (!j.dueDate) return {label:'交期待补',tone:'neutral',days:null};
    const days = Math.round((Date.parse(j.dueDate+'T00:00:00Z')-Date.parse(foDate()+'T00:00:00Z'))/86400000);
    return {label:days<0?`逾期 ${-days} 天`:days===0?'今天交货':days<=3?`${days} 天后交货`:j.dueDate,tone:days<0?'danger':days<=3?'amber':'green',days};
  }
  const feTag = (label,tone='neutral') => `<span class="fe-tag ${tone}">${esc(label)}</span>`;
  const feOrderLabel = id => {
    const j=factoryJobRecords.find(x=>x.id===id);
    return j ? `${j.community || '项目待补'} · ${j.customer}` : '原订单已不存在';
  };
  function feTask(label,detail,action,id,tone='neutral') {
    return `<button class="fe-task ${tone}" type="button" data-action="${action}" data-id="${esc(id)}"><span class="fe-task-dot"></span><span><b>${esc(label)}</b><small>${esc(detail)}</small></span><i>→</i></button>`;
  }
  function feHandoffPanel(j) {
    const count=feChecklist.filter(([key])=>j.handoff?.[key]).length,missing=feMissing(j),due=feDue(j);
    return panel('接单交接与交期','尺寸、配置、增项确认后再安排生产',
      `<div class="fe-readiness"><div><b>${count}<small> / ${feChecklist.length}</small></b><span>交接确认</span></div><div>${feTag(due.label,due.tone)}${feTag(j.priority || '正常排期',j.priority==='加急'?'amber':'neutral')}<p>${esc(j.dueDate || '未约定交期')} · ${esc(j.responsible || '负责人待补')}</p></div></div>`+
      `<div class="fe-checklist">${feChecklist.map(([key,label])=>`<span class="${j.handoff?.[key]?'confirmed':''}"><i>${j.handoff?.[key]?'✓':'○'}</i>${esc(label)}</span>`).join('')}</div>`+
      `<p class="fe-tip">${missing.length?'待补：'+esc(missing.join('、')):'本户接单交接已确认。'} · 确认项变更后请重新核对。</p>`+
      `<div class="fo-actions">${foBtn('核对交接清单','fe-handoff',j.id,true)}${foBtn('调整交期 / 优先级','fe-schedule',j.id)}</div>`+
      `<details><summary>交接与排期历史 (${(j.handoffHistory||[]).length})</summary>${foTable(['时间 / 经手人','变更记录'],[...(j.handoffHistory||[])].reverse().map(h=>`<tr><td>${esc(h.date)}<br>${esc(h.operator)}</td><td>${esc(h.note)}</td></tr>`))}</details>`
    );
  }
  function feBlockerPanel(j) {
    const list=foState.blockers.filter(b=>b.orderId===j.id);
    return panel('生产异常与处理','缺料、待确认、返工及时交接，解决后保留结果',
      `<div class="fo-actions">${foBtn('＋ 记录异常','fe-blocker',j.id,true)}</div>`+
      (list.length?`<div class="fe-blockers">${[...list].reverse().map(b=>`<article class="fe-blocker ${b.resolved?'resolved':''}"><div>${feTag(b.resolved?'已解决':b.kind,b.resolved?'green':'danger')}<small>${esc(b.date)}</small></div><b>${esc(b.content)}</b><p>处理人 ${esc(b.owner)} · ${b.due?`计划 ${esc(b.due)}`:'处理时间待补'}</p>${b.resolved?`<p>结论：${esc(b.resolution)} · ${esc(b.resolvedDate)} · ${esc(b.resolvedBy)}</p>`:''}${foBtn(b.resolved?'重新开启':'登记解决结果','fe-blocker-close',b.id)}<details><summary>处理历史 (${(b.history||[]).length})</summary>${(b.history||[]).map(h=>`<p>${esc(h.date)} · ${esc(h.operator)} · ${esc(h.note)}</p>`).join('')}</details></article>`).join('')}</div>`:'<div class="fe-empty"><span>✓</span><b>暂未登记生产异常</b><p>发现问题就记录责任人和处理时间，避免只在口头交接。</p></div>')
    );
  }
  factoryHome=function() {
    const active=feActive(),blockers=feOpenBlockers(),missing=active.filter(j=>feMissing(j).length),urgent=active.filter(j=>feDue(j).days!==null&&feDue(j).days<=3);
    const low=foState.items.filter(i=>i.qty<=i.safety),today=foState.attendance.filter(a=>a.date===foDate());
    const unpaidAttendance=foState.employees.filter(e=>e.active!==false&&!today.some(a=>a.employeeId===e.id));
    const external=foState.outsources.filter(o=>!['已验收','取消'].includes(o.status));
    const monthOut=foState.cash.filter(c=>!c.void&&c.direction==='out'&&c.date.startsWith(foMonth)).reduce((n,c)=>n+c.amount,0)+foState.payments.filter(p=>!p.void&&p.type==='退款'&&p.date.startsWith(foMonth)).reduce((n,p)=>n+p.amount,0);
    const queue=[...blockers.map(b=>feTask('生产异常 · '+b.kind,feOrderLabel(b.orderId)+' · '+b.owner,'fo-order-open',b.orderId,'danger')),
      ...urgent.map(j=>feTask(feDue(j).label,j.community+' · '+j.customer+' · '+j.status,'fo-order-open',j.id,'amber')),
      ...missing.map(j=>feTask('接单交接待完善',j.community+' · '+j.customer+' · '+feMissing(j).length+' 项待核对','fo-order-open',j.id)),
      ...low.map(i=>feTask('配件需要补货',i.name+' · 剩 '+i.qty+i.unit+' / 安全量 '+i.safety+i.unit,'fe-inventory','')),
      ...external.map(o=>feTask('外协待完成',feOrderLabel(o.orderId)+' · '+o.name+' · '+(o.due||'交期待补'),'fo-order-open',o.orderId))];
    if(unpaidAttendance.length)queue.push(feTask('今日考勤待登记',unpaidAttendance.map(e=>e.name).join('、'),'fe-attendance',''));
    const sorted=[...active].sort((a,b)=>(a.dueDate||'9999').localeCompare(b.dueDate||'9999'));
    return `<div class="fe-workspace">${head('FACTORY / DAILY WORKSPACE','工厂 · 今日工作台','交接清楚再生产，材料用到哪户，成本就记到哪户。',foBtn('扫描报价接单','fo-summary-scan')+foBtn('＋ 新建订单','fo-order-new','',true))}
      <section class="fe-hero"><div><span class="fe-eyebrow">${foDate().replaceAll('-',' / ')} · 生产与交付</span><h2>把今天的事，落到每一户。</h2><p>${active.length} 户正在推进 · ${active.filter(j=>!j.dueDate).length} 户待补交期 · ${blockers.length} 项生产异常待处理</p></div><div class="fe-hero-stats"><button data-action="fe-queue"><b>${urgent.length}</b><span>临期 / 逾期订单</span></button><button data-action="fe-queue"><b>${missing.length}</b><span>交接待完善</span></button><button data-action="fe-queue"><b>${blockers.length}</b><span>待处理异常</span></button></div></section>
      <div class="fo-entries">${foEntry('生产订单',`${factoryJobRecords.length} 户`,`${active.length} 户未出货 · 材料、进程、收款`,'production')}${foEntry('配件出入库',`${foState.items.length} 类`,`${low.length} 类库存预警 · 余料复用`,'inventory')}${foEntry('工人考勤',`${foState.employees.filter(e=>e.active!==false).length} 人`,`${today.length} 人今日已登记 · 月度工资`,'attendance')}${foEntry('收入与支出',money(monthOut),`${foMonth} 实际支出 · 订单直接毛利`,'expenses')}</div>
      <div class="fe-dashboard-grid"><div>${panel('待交付订单','按约定交期排序，未约定日期的订单显示在后',foTable(['客户 / 项目','工序','交期 / 交接','操作'],sorted.map(j=>`<tr><td><b>${esc(j.community||'项目待补')}</b><small class="fe-cell-sub">${esc(j.customer)} · ${esc(j.source||'来源待补')}</small></td><td>${feTag(j.status)}${feOpenBlockers(j.id).length?feTag(feOpenBlockers(j.id).length+' 项异常','danger'):''}</td><td>${feTag(feDue(j).label,feDue(j).tone)}<small class="fe-cell-sub">${feMissing(j).length?'交接 '+feMissing(j).length+' 项待补':'交接已确认'}</small></td><td>${foBtn('本户档案 →','fo-order-open',j.id)}</td></tr>`)),'<button class="btn" data-page="production">全部订单 →</button>')}</div><aside id="feQueue">${panel('今天要处理','根据实际登记资料生成，点击进入对应订单',`<div class="fe-task-list">${queue.length?queue.join(''):'<div class="fe-empty"><span>✓</span><b>暂无待处理事项</b><p>交期、库存及考勤资料完整时，提醒会更准确。</p></div>'}</div>`)}</aside></div>
      <div class="fe-footnote">所有提醒来自本机登记资料。交接提醒帮助核对，不替代厂长对开工条件的确认。</div></div>`;
  };
  const feOrderPage=factoryOrderDetailPage;
  factoryOrderDetailPage=function() {
    const j=foJob(),html=feOrderPage();if(!j)return html;
    const nav=`<nav class="fe-order-nav" aria-label="订单页快捷定位">${[['feHandoff','交接 / 异常'],['feDocuments','图纸与版本'],['feMaterial','基础配置'],['feProgress','生产进程'],['feCosts','材料与成本'],['feCash','收款与付款'],['feExternal','外协报货']].map(([id,label])=>foBtn(label,'fe-jump',id)).join('')}</nav>`;
    let result=html.replace('<div class="cards">',nav+'<div class="cards">');
    result=result.replace('<section class="panel">',`<div class="grid-2 fe-order-coordination" id="feHandoff">${feHandoffPanel(j)}${feBlockerPanel(j)}</div><section class="panel">`);
    for(const [title,id] of [['本户基础材料与要求','feMaterial'],['生产进程','feProgress'],['材料、五金与成本','feCosts'],['收款与付款','feCash'],['外协报货 · 玻璃门 / 特殊工艺','feExternal']]) {
      const marker=`<section class="panel"><div class="panel-head"><div><h3>${title}`;
      result=result.replace(marker,`<section class="panel" id="${id}"><div class="panel-head"><div><h3>${title}`);
    }
    const reuse=foState.offcutMoves.filter(m=>m.orderId===j.id);
    if(reuse.length)result+=panel('本户余料复用','实物使用记录，原采购成本不在这里重复计入',foTable(['日期','规格','数量变化','经手人 / 用途'],reuse.map(m=>`<tr><td>${esc(m.date)}</td><td>${esc(m.description)}</td><td>${m.delta>0?'+':''}${m.delta} ${esc(foState.offcuts.find(o=>o.id===m.offcutId)?.unit||'块')}</td><td>${esc(m.operator)} · ${esc(m.note)}</td></tr>`)));
    return `<div class="fe-order">${result}</div>`;
  };
  function feOffcutsPanel() {
    const list=foState.offcuts.filter(o=>!feOffcutSearch||[o.brand,o.substrate,o.color,o.model,o.thickness,o.length,o.width,o.location,o.sourceHousehold,o.batch,feOrderLabel(o.orderId)].join(' ').toLowerCase().includes(feOffcutSearch.toLowerCase()));
    return panel('可复用板材余料','记录真实尺寸、花色、纹理方向与位置；采购前先查看现有余料',
      `<div class="toolbar"><input class="field" id="feOffcutSearch" placeholder="品牌 / 花色 / 型号 / 尺寸 / 位置" value="${esc(feOffcutSearch)}">${foBtn('查找余料','fe-offcut-search')}${foBtn('＋ 登记余料','fe-offcut','',true)}</div>`+
      foTable(['板材 / 花色','尺寸与纹理','位置 / 来源','剩余','操作'],list.map(o=>`<tr><td><b>${esc(o.brand)} · ${esc(o.color)}</b><small class="fe-cell-sub">${esc([o.substrate,o.thickness+'mm',o.model].filter(Boolean).join(' / '))}</small></td><td>${o.length} × ${o.width} mm<br>${esc(o.grain)}</td><td>${esc(o.location)}<small class="fe-cell-sub">${esc([o.sourceHousehold,o.batch,o.orderId?feOrderLabel(o.orderId):'期初 / 来源待补'].filter(Boolean).join(' · '))}</small></td><td><b>${o.qty} ${esc(o.unit||'块')}</b></td><td>${o.qty>0?foBtn('领用到订单','fe-offcut-use',o.id):feTag('已用完')}${foBtn('更正数量','fe-offcut-adjust',o.id)}</td></tr>`),feOffcutSearch?'未找到匹配余料。更换关键词或查看采购前的真实库存。':'暂无余料。将可用余料贴标签，登记后能按尺寸与位置查找。')+
      `<details><summary>余料使用与更正记录 (${foState.offcutMoves.length})</summary>${foTable(['日期 / 经手人','板材','数量变化','用途 / 说明','操作'],[...foState.offcutMoves].reverse().map(m=>`<tr><td>${esc(m.date)}<br>${esc(m.operator)}</td><td>${esc(m.description)}</td><td>${m.delta>0?'+':''}${m.delta} ${esc(foState.offcuts.find(o=>o.id===m.offcutId)?.unit||'块')}</td><td>${esc(m.orderId?feOrderLabel(m.orderId):'库存更正')}<br>${esc(m.note)}</td><td>${m.type==='use'&&-m.delta>foState.offcutMoves.filter(r=>r.sourceId===m.id).reduce((n,r)=>n+r.delta,0)?foBtn('未用退回','fe-offcut-return',m.id):''}</td></tr>`))}</details><p class="fe-tip">这里只记录实物复用，不重复增加订单成本，不自动估算节省金额；余料原采购成本沿用原单记录。</p>`).replace('<section class="panel">','<section class="panel" id="feOffcutStock">');
  }
  const feInventory=inventory;
  inventory=function(){return feInventory().replace('<div class="cards">',`<nav class="fe-order-nav">${foBtn('配件与库存流水','fe-jump','feHardwareStock')}${foBtn('余料登记与复用','fe-jump','feOffcutStock')}</nav><div class="cards" id="feHardwareStock">`)+feOffcutsPanel()};
  const feOrderForm=foOrderForm;
  foOrderForm=function(j={}) {
    feOrderForm(j);
    const fields=$('#foOrderForm .fo-fields');
    if(fields)fields.insertAdjacentHTML('beforeend',foField('dueDate','约定交货日期（可后补）',j.dueDate,'date')+foSelect('priority','排期优先级',['正常排期','加急'],j.priority));
  };
  const feRenderReview=foRenderReview;
  foRenderReview=function(rows,kind,text,header={}) {
    feRenderReview(rows,kind,text,header);
    if($('#foBillForm [name=stock]')?.value!=='yes')return;
    $('#factoryOcrReview').insertAdjacentHTML('afterbegin','<div class="fe-pack-note">包装换算请按原单核对：例如 2 包，每包 1000 个，库存登记 2000 个；采购数量和原单金额保留。未换算时保留原单位、倍数 1。规格里的“5×20”是尺寸，不能当包装数量。</div>');
    $('#factoryOcrReview').querySelectorAll('[data-ocr-row]').forEach((el,i)=>el.insertAdjacentHTML('beforeend',`<label>库存 / 领用单位<input class="field" data-ocr-field="stockUnit" placeholder="留空沿用原单位" value="${esc(rows[i]?.stockUnit||'')}"></label><label>每采购单位包含库存数量<input class="field" data-ocr-field="packFactor" type="number" min="0.000001" step="any" value="${esc(rows[i]?.packFactor||1)}"></label>`));
  };
  function feStockQty(line) {return foN(Number(line.qty)*Number(line.packFactor||1));}
  function feStockBookValue(item) {
    // Existing balances become an opening baseline; old movements are never rewritten.
    return Number.isFinite(item.bookValue)?foN(item.bookValue):foN(item.qty*item.avg);
  }
  function feMoneyAlloc(total,weights) {
    // Allocate whole cents by largest remainder: no negative final line or missing cent.
    const cents=Math.round(foN(total)*100),units=weights.map(w=>Math.round(foN(w)*100));
    if(!Number.isSafeInteger(cents)||cents<0||units.some(n=>!Number.isSafeInteger(n)||n<0))throw Error('Invalid allocation amount');
    const gross=units.reduce((n,w)=>n+BigInt(w),0n);
    if(gross<=0n)throw Error('Invalid allocation weights');
    const parts=units.map((w,index)=>{const numerator=BigInt(cents)*BigInt(w);return {index,cents:Number(numerator/gross),remainder:numerator%gross}});
    const left=cents-parts.reduce((n,p)=>n+p.cents,0);
    const rank=[...parts].sort((a,b)=>a.remainder===b.remainder?a.index-b.index:a.remainder>b.remainder?-1:1);
    for(let n=0;n<left;n++)rank[n].cents++;
    return parts.map(p=>p.cents/100);
  }
  function feStockConversionError(lines) {
    for(const l of lines){
      const factor=Number(l.packFactor||1),qty=Number(l.qty)*factor,unit=(l.stockUnit||l.unit).trim();
      if(!Number.isFinite(factor)||factor<=0||!Number.isFinite(qty)||qty<=0||!Number.isFinite(feStockQty(l))||feStockQty(l)<=0||Math.abs(qty-foN(qty))>0.000001)return '包装换算倍数需为正数，换算后库存数量须大于0且最多保留两位小数';
      if(/^(个|套|副|支|块|张|盘|卷|包|件|把|根)$/.test(unit)&&!Number.isInteger(feStockQty(l)))return '按个、套、张等计数的库存数量需为整数，请核对包装换算';
    }
    return '';
  }
  function fePostInvoiceStock(v,lines,total,billId) {
    const allocations=feMoneyAlloc(total,lines.map(l=>l.amount));
    lines.forEach((l,index)=>{
      const model=[l.productCode,l.spec].filter(Boolean).join(' / '),brand=l.brand||'',unit=(l.stockUnit||l.unit).trim(),qty=feStockQty(l),factor=Number(l.packFactor||1);
      const match=foState.items.find(i=>i.name===l.product&&i.model===model&&i.brand===brand&&i.unit===unit);
      const item=match||{id:foId(),name:l.product,model,brand,unit,qty:0,avg:0,safety:0};if(!match)foState.items.push(item);
      const amount=allocations[index],unitCost=amount/qty;
      item.bookValue=foN(feStockBookValue(item)+amount);item.avg=foAverage(item.bookValue/(item.qty+qty));item.qty=foN(item.qty+qty);
      foState.moves.push({id:foId(),type:'in',itemId:item.id,date:v.date,name:item.name,model:item.model,unit:item.unit,qty,unitCost,amount,supplier:v.supplier,billNo:v.billNo,operator:v.operator,fileId:billId,purchaseQty:l.qty,purchaseUnit:l.unit,packFactor:factor});
    });
  }
  const feBillSignature=foBillSignature;
  foBillSignature=function(v,lines,projectId) {
    const raw=feBillSignature(v,lines,projectId);
    if(projectId!=='inventory'||!lines.some(l=>Number(l.packFactor||1)!==1||(l.stockUnit||l.unit).trim()!==l.unit.trim()))return raw;
    return JSON.stringify({...JSON.parse(raw),inventoryUnits:lines.map(l=>[(l.stockUnit||l.unit).trim(),Number(l.packFactor||1)])});
  };
  const feAction=action;
  action=function(name,btn) {
    if(!name.startsWith('fe-'))return feAction(name,btn);
    const id=btn.dataset.id||'',j=factoryJobRecords.find(x=>x.id===id)||foJob();
    if(name==='fe-jump'){document.getElementById(id)?.scrollIntoView({behavior:'smooth',block:'start'});return}
    if(name==='fe-queue'){document.getElementById('feQueue')?.scrollIntoView({behavior:'smooth',block:'start'});return}
    if(name==='fe-offcut-search'){feOffcutSearch=$('#feOffcutSearch')?.value.trim()||'';render();document.getElementById('feOffcutStock')?.scrollIntoView({block:'start'});return}
    if(name==='fe-inventory'||name==='fe-attendance'){module='factory';page=name==='fe-inventory'?'inventory':'attendance';render();return}
    if(name==='fe-handoff'&&j){
      openModal('本户接单交接 · '+j.customer,foForm('foHandoffForm',`<input type="hidden" name="orderId" value="${esc(j.id)}"><p class="fo-wide">请对照客户报价、图纸和材料约定逐项确认。未核对的项目保持未勾选。</p>`+
        feChecklist.map(([key,label])=>`<label class="fo-wide"><input type="checkbox" name="${key}" ${j.handoff?.[key]?'checked':''}>${esc(label)}</label>`).join('')+foField('operator','确认人','','text',true)+foField('date','确认日期',foDate(),'date',true)+foArea('note','核对说明 / 待补事项')));return;
    }
    if(name==='fe-schedule'&&j){openModal('交期与排期',foForm('foScheduleForm',`<input type="hidden" name="orderId" value="${esc(j.id)}">`+foField('dueDate','约定交货日期',j.dueDate,'date',true)+foSelect('priority','优先级',['正常排期','加急'],j.priority)+foField('operator','经手人','','text',true)+foArea('note','调整原因 / 与客户约定')));return}
    if(name==='fe-blocker'&&j){openModal('记录本户生产异常',foForm('foBlockerForm',`<input type="hidden" name="orderId" value="${esc(j.id)}">`+foSelect('kind','异常类型',['缺料 / 待到货','图纸 / 尺寸待确认','外协延迟','设备故障','返工','其他'])+foField('owner','负责处理人','','text',true)+foField('operator','记录人','','text',true)+foField('date','发现日期',foDate(),'date',true)+foField('due','预计处理日期','','date')+foArea('content','具体问题与需要的协助')));return}
    if(name==='fe-blocker-close'){
      const b=foState.blockers.find(x=>x.id===id);if(!b)return;
      openModal(b.resolved?'重新开启异常':'登记异常解决结果',foForm('foBlockerResolveForm',`<input type="hidden" name="recordId" value="${esc(id)}"><p class="fo-wide">${esc(b.content)}</p>`+foField('operator','操作人','','text',true)+foField('date','操作日期',foDate(),'date',true)+foArea('note',b.resolved?'重新开启原因':'处理结果 / 完成说明')));return;
    }
    if(name==='fe-offcut'){
      openModal('登记可复用余料',foForm('foOffcutForm',foField('brand','板材品牌','','text',true)+foField('substrate','基材','','text',true)+foField('thickness','厚度 mm','','number',true)+foField('color','颜色 / 花色','','text',true)+foField('model','花色 / 型号')+foSelect('grain','纹理方向',['顺长度方向','顺宽度方向','无方向要求','待确认'])+foField('length','实际长度 mm','','number',true)+foField('width','实际宽度 mm','','number',true)+foField('qty','相同规格块数',1,'number',true)+foField('location','存放位置 / 标签号','','text',true)+foSelect('orderId','来源订单',[['','期初 / 暂不关联'],...foOrderOpts()])+foField('operator','登记人','','text',true)+foField('date','日期',foDate(),'date',true)+foArea('note','可用情况 / 缺口说明')));return;
    }
    if(name==='fe-offcut-use'||name==='fe-offcut-adjust'||name==='fe-offcut-return'){
      const original=name==='fe-offcut-return'?foState.offcutMoves.find(x=>x.id===id&&x.type==='use'):null;
      const o=foState.offcuts.find(x=>x.id===(original?.offcutId||id));if(!o)return;
      const using=name==='fe-offcut-use',returning=!!original;
      if(using&&!factoryJobRecords.length){toast('先建立领用订单');return}
      openModal(using?'余料领用到订单':returning?'未使用余料退回':'余料数量更正',foForm('foOffcutMoveForm',`<input type="hidden" name="recordId" value="${esc(o.id)}"><input type="hidden" name="sourceId" value="${esc(original?.id||'')}"><input type="hidden" name="type" value="${using?'use':returning?'return':'adjust'}"><p class="fo-wide">${esc(o.brand)} · ${esc(o.color)} · ${o.length} × ${o.width} × ${o.thickness} mm · 现存 ${o.qty} 块</p>`+
        (using?foSelect('orderId','领用订单',foOrderOpts()):returning?`<p class="fo-wide">原领用订单：${esc(feOrderLabel(original.orderId))}</p>`:foSelect('direction','更正方式',[['in','补增数量'],['out','冲减数量']]))+
        foField('qty','块数',1,'number',true)+foField('operator','经手人','','text',true)+foField('date','日期',foDate(),'date',true)+foArea('note','领用用途 / 退回或更正原因')));return;
    }
  };
  const feExtraSubmit=foExtraSubmit;
  foExtraSubmit=function(form,v,j) {
    if(form.getAttribute('id')==='foOrderForm'){
      const old=factoryJobRecords.find(x=>x.id===editingFactoryJobId);
      if(old){
        const changed=[['quote',['quote','settled','product']],['board',['boardBrand','substrate','thickness','boardColor','boardModel']],['hardware',['hardwareSummary']],['requirements',['requirements']]].filter(([,fields])=>fields.some(k=>String(v[k]??'')!==String(old[k]??'')));
        if(changed.length){v.handoff={...(old.handoff||{})};changed.forEach(([key])=>v.handoff[key]=false);v.handoffHistory=[...(old.handoffHistory||[]),{date:foDate(),operator:'编辑接单信息',note:'配置 / 约定有变更，已撤回相关交接确认：'+changed.map(([key])=>feChecklist.find(([k])=>k===key)[1]).join('、')}];}
        if(String(v.dueDate||'')!==String(old.dueDate||'')||String(v.priority||'正常排期')!==String(old.priority||'正常排期'))v.handoffHistory=[...(v.handoffHistory||old.handoffHistory||[]),{date:foDate(),operator:'编辑接单信息',note:`排期修改：${old.dueDate||'未约定'} → ${v.dueDate||'未约定'}；${v.priority}`}];
      }
      return feExtraSubmit(form,v,j);
    }
    if(!['foHandoffForm','foScheduleForm','foBlockerForm','foBlockerResolveForm','foOffcutForm','foOffcutMoveForm'].includes(form.getAttribute('id')))return feExtraSubmit(form,v,j);
    const fail=message=>{toast(message);return true};
    if(!v.operator?.trim())return fail('填写操作人 / 经手人');
    if(form.getAttribute('id')==='foHandoffForm'||form.getAttribute('id')==='foScheduleForm'){
      const job=factoryJobRecords.find(x=>x.id===v.orderId);if(!job)return fail('订单不存在');
      if(foCommit(()=>{
        job.handoffHistory||=[];
        if(form.getAttribute('id')==='foHandoffForm'){
          job.handoff=Object.fromEntries(feChecklist.map(([key])=>[key,form.elements[key].checked]));
          job.handoffHistory.push({date:v.date,operator:v.operator,note:feChecklist.map(([key,label])=>`${job.handoff[key]?'已确认':'待核对'}：${label}`).join('；')+'。'+v.note});
        }else{
          job.handoffHistory.push({date:foDate(),operator:v.operator,note:`交期 ${job.dueDate||'未约定'} → ${v.dueDate}；${v.priority}；${v.note}`});job.dueDate=v.dueDate;job.priority=v.priority;
        }
      }))foDone('交接 / 排期已保存');return true;
    }
    if(form.getAttribute('id')==='foBlockerForm'){
      if(!factoryJobRecords.some(x=>x.id===v.orderId)||!v.content.trim()||!v.owner.trim())return fail('填写异常内容和处理人');
      if(v.due&&v.due<v.date)return fail('预计处理日期不能早于发现日期');
      if(foCommit(()=>foState.blockers.push({...v,id:foId(),resolved:false,history:[{date:v.date,operator:v.operator,note:'登记异常：'+v.content}]})))foDone('异常已加入本户档案和首页待办');return true;
    }
    if(form.getAttribute('id')==='foBlockerResolveForm'){
      const b=foState.blockers.find(x=>x.id===v.recordId);if(!b||!v.note.trim())return fail('填写处理结果或重新开启原因');
      if(v.date<b.date)return fail('处理日期不能早于发现日期');
      if(foCommit(()=>{b.resolved=!b.resolved;b.resolution=v.note;b.resolvedDate=v.date;b.resolvedBy=v.operator;(b.history||=[]).push({date:v.date,operator:v.operator,note:(b.resolved?'已解决：':'重新开启：')+v.note})}))foDone('异常处理已留痕');return true;
    }
    if(form.getAttribute('id')==='foOffcutForm'){
      if(['qty','thickness','length','width'].some(k=>!Number.isFinite(Number(v[k]))||Number(v[k])<=0))return fail('尺寸、厚度和数量需为正数，数量支持半张');
      if(!v.brand.trim()||!v.substrate.trim()||!v.color.trim()||!v.location.trim())return fail('补全品牌、基材、花色与存放位置');
      if(v.orderId&&!factoryJobRecords.some(x=>x.id===v.orderId))return fail('来源订单不存在');
      if(foCommit(()=>foState.offcuts.push({...v,id:foId(),qty:Number(v.qty),thickness:Number(v.thickness),length:Number(v.length),width:Number(v.width)})))foDone('余料已登记，采购前可先查看复用');return true;
    }
    if(form.getAttribute('id')==='foOffcutMoveForm'){
      const o=foState.offcuts.find(x=>x.id===v.recordId),qty=Number(v.qty),source=foState.offcutMoves.find(x=>x.id===v.sourceId&&x.type==='use');
      if(!o||!Number.isFinite(qty)||qty<=0||!v.note.trim())return fail('填写正数数量和用途 / 原因');
      if(v.type==='use'&&!factoryJobRecords.some(x=>x.id===v.orderId))return fail('选择有效客户订单');
      if(v.type==='return'&&(!source||source.offcutId!==o.id||qty>-source.delta-foState.offcutMoves.filter(r=>r.sourceId===source.id).reduce((n,r)=>n+r.delta,0)))return fail('退回不能超过原领用剩余数量');
      if(v.type==='return'&&v.date<source.date)return fail('退回日期不能早于原领用日期');
      if(v.date<o.date)return fail('余料变动日期不能早于登记日期');
      const delta=(v.type==='use'||v.type==='adjust'&&v.direction==='out')?-qty:qty;
      if(o.qty+delta<0)return fail('余料数量不足，核对后再领用或冲减');
      if(foCommit(()=>{o.qty+=delta;foState.offcutMoves.push({...v,id:foId(),offcutId:o.id,orderId:v.type==='use'?v.orderId:v.type==='return'?source.orderId:'',delta,description:[o.brand,o.substrate,o.color,`${o.length}×${o.width}×${o.thickness}mm`].join(' / ')});}))foDone('余料变化已记录，未重复记入采购成本');return true;
    }
    return true;
  };
