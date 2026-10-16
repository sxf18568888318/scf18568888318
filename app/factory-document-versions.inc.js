  // Versioned production references. Original binaries remain in the existing local file store.
  if(!Array.isArray(foState.productionDocuments))foState.productionDocuments=[];
  const fdKinds=['生产图纸','客户报价单','柜门 / 工艺确认','其他生产资料'];
  const fdHandoffKeys={'生产图纸':['drawing'],'客户报价单':['quote'],'柜门 / 工艺确认':['board','requirements']};
  const fdLatest=(orderId,kind)=>foState.productionDocuments.filter(d=>d.orderId===orderId&&d.kind===kind).at(-1);
  function fdPanel(j) {
    const docs=foState.productionDocuments.filter(d=>d.orderId===j.id);
    return panel('生产资料与版本','新图纸到来时撤回对应交接确认，旧版原件继续保留',
      `<div class="fo-actions">${foBtn('＋ 上传图纸 / 报价原件','fd-upload',j.id,true)}</div>`+
      foTable(['类别 / 版本','文件 / 说明','确认状态','操作'],[...docs].reverse().map(d=>{
        const latest=fdLatest(j.id,d.kind)?.id===d.id;
        return `<tr><td><b>${esc(d.kind)}</b><small class="fe-cell-sub">${esc(d.revision)} · ${esc(d.date)} · ${esc(d.operator)}</small></td><td>${esc(d.name)}<small class="fe-cell-sub">${esc(d.note)}</small></td><td>${feTag(!latest?'已有新版':d.confirmed?'当前已确认':'当前待确认',!latest?'neutral':d.confirmed?'green':'amber')}${d.confirmed?`<small class="fe-cell-sub">${esc(d.confirmedBy)} · ${esc(d.confirmedDate)}</small>`:''}</td><td>${foBtn('查看原件','fd-view',d.id)}${latest&&!d.confirmed?foBtn('确认此版','fd-confirm',d.id):''}</td></tr>`;
      }),'暂无原件；可上传图片、PDF、Excel 或 CAD 文件，纸质交接也可手动核对。')+
      '<p class="fe-tip">生产按当前已确认资料交接。CAD 等文件保留原件，由本机对应软件打开；这里不进行自动拆单或排板。</p>',
      '<span class="fe-tag">保留全部版本</span>').replace('<section class="panel">','<section class="panel" id="feDocuments">');
  }
  const fdOrderPage=factoryOrderDetailPage;
  factoryOrderDetailPage=function(){
    const j=foJob(),html=fdOrderPage();if(!j)return html;
    return html.replace('<section class="panel" id="feMaterial">',fdPanel(j)+'<section class="panel" id="feMaterial">');
  };
  const fdAction=action;
  action=function(name,btn){
    if(!name.startsWith('fd-'))return fdAction(name,btn);
    const id=btn.dataset.id||'';
    if(name==='fd-view'){viewFactoryBillFile(id);return}
    if(name==='fd-upload'){
      const j=factoryJobRecords.find(x=>x.id===id);if(!j)return;
      openModal('本户生产资料 · 上传新版本',foForm('foProductionDocumentForm',`<input type="hidden" name="orderId" value="${esc(j.id)}">`+foSelect('kind','资料类别',fdKinds)+foField('revision','版本名称（例如 V2 / 客户确认版）','','text',true)+foField('date','登记日期',foDate(),'date',true)+foField('operator','登记人','','text',true)+'<label class="fo-wide">原始文件<input class="field" type="file" name="document" required accept="image/*,.pdf,.xlsx,.xls,.csv,.dwg,.dxf"></label>'+foArea('note','与上一版的差异 / 说明')+'<p class="fo-wide">上传新图纸 / 报价后，对应交接确认需重新核对；原有版本保留。</p>'));return;
    }
    if(name==='fd-confirm'){
      const d=foState.productionDocuments.find(x=>x.id===id);if(!d)return;
      openModal('确认当前生产资料版本',foForm('foProductionDocumentConfirmForm',`<input type="hidden" name="recordId" value="${esc(id)}"><p class="fo-wide">${esc(d.kind)} · ${esc(d.revision)} · ${esc(d.name)}。请按原件核对，确认可作为本户当前生产依据。</p>`+foField('operator','确认人','','text',true)+foArea('note','确认说明'),'确认此版本'));return;
    }
  };
  const fdExtra=foExtraSubmit;
  foExtraSubmit=function(form,v,j){
    if(form.getAttribute('id')==='foHandoffForm'){
      for(const [kind,keys] of Object.entries(fdHandoffKeys)){
        const latest=fdLatest(v.orderId,kind);
        if(keys.some(key=>form.elements[key].checked)&&latest&&!latest.confirmed){toast('先核对并确认当前'+kind+'版本，再勾选交接确认');return true}
      }
    }
    if(form.getAttribute('id')==='foProductionDocumentForm')return fdSaveDocument(form,v);
    if(form.getAttribute('id')==='foProductionDocumentConfirmForm'){
      const d=foState.productionDocuments.find(x=>x.id===v.recordId);
      if(!d||fdLatest(d.orderId,d.kind)?.id!==d.id){toast('已有新版，请核对并确认最新资料');return true}
      if(!v.operator.trim()){toast('填写确认人');return true}
      if(foCommit(()=>{d.confirmed=true;d.confirmedBy=v.operator;d.confirmedDate=foDate();d.confirmationNote=v.note}))foDone('此版本已确认；接单交接清单仍需逐项核对');return true;
    }
    return fdExtra(form,v,j);
  };
  async function fdSaveDocument(form,v){
    const job=factoryJobRecords.find(x=>x.id===v.orderId),file=form.elements.document.files[0];
    if(!job||!file||!v.operator.trim()||!v.revision.trim()){toast('选择原件并填写版本与登记人');return true}
    const hash=await foFileHash(file);if(!form.isConnected)return true;
    const duplicate=()=>foState.productionDocuments.some(d=>d.orderId===job.id&&d.kind===v.kind&&d.hash===hash);
    if(duplicate()){toast('此原件已存档，请确认现有版本，避免重复上传');return true}
    const id=foId();await saveFactoryBillFile(id,file);if(!form.isConnected)return true;
    if(duplicate()){toast('此原件刚刚已存档，请核对现有版本');return true}
    if(foCommit(()=>{
      foState.productionDocuments.push({...v,id,name:file.name,mime:file.type,hash,confirmed:false});
      const keys=fdHandoffKeys[v.kind]||[];
      if(keys.length){job.handoff={...(job.handoff||{})};keys.forEach(key=>job.handoff[key]=false);(job.handoffHistory||=[]).push({date:v.date,operator:v.operator,note:`上传${v.kind} ${v.revision}，撤回对应交接确认，等待重新核对。`});}
    }))foDone('新版本原件已存档，旧版继续保留');return true;
  }
