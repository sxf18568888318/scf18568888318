begin;

-- Temporary DDL privilege needed only while assigning SECURITY DEFINER functions to the executor owner.
grant create on schema factory_private to anju_custom_executor;

create table if not exists factory_private.purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references factory_private.work_orders(id),
  document_kind text not null check (document_kind in ('板材单','五金单')),
  supplier text not null default '',
  bill_no text not null default '',
  bill_date date not null default current_date,
  subtotal numeric(14,2) not null check (subtotal >= 0),
  freight numeric(14,2) not null default 0 check (freight >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  landed_total numeric(14,2) not null check (landed_total > 0),
  declared_total numeric(14,2),
  status text not null default '已核对' check (status in ('已核对')),
  note text not null default '',
  created_by uuid not null,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  unique(created_by,request_id)
);

create table if not exists factory_private.purchase_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references factory_private.purchase_invoices(id),
  line_no integer not null check (line_no > 0),
  material_id uuid not null references factory_private.materials(id),
  product_snapshot text not null,
  spec_snapshot text not null default '',
  unit_snapshot text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,4) not null check (unit_price >= 0),
  amount numeric(14,2) not null check (amount >= 0),
  landed_amount numeric(14,2) not null check (landed_amount >= 0),
  inventory_movement_id uuid not null references factory_private.inventory_movements(id),
  note text not null default '',
  unique(invoice_id,line_no)
);

alter table factory_private.order_documents
  add column if not exists purchase_invoice_id uuid references factory_private.purchase_invoices(id);

do $$ declare t text; begin
  foreach t in array array['purchase_invoices','purchase_invoice_lines'] loop
    execute format('alter table factory_private.%I enable row level security',t);
    execute format('alter table factory_private.%I force row level security',t);
    execute format('drop policy if exists factory_executor_access on factory_private.%I',t);
    execute format('create policy factory_executor_access on factory_private.%I for all to anju_custom_executor using (true) with check (true)',t);
  end loop;
end $$;

grant select,insert,update on factory_private.purchase_invoices,factory_private.purchase_invoice_lines to anju_custom_executor;
revoke all on factory_private.purchase_invoices,factory_private.purchase_invoice_lines from public,anon,authenticated;

create or replace function api.factory_receive_purchase_invoice(
  p_order_id uuid,
  p_document_kind text,
  p_supplier text,
  p_bill_no text,
  p_bill_date date,
  p_freight numeric,
  p_discount numeric,
  p_declared_total numeric,
  p_lines jsonb,
  p_documents jsonb,
  p_paid boolean,
  p_payment_method text,
  p_note text,
  p_request_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path=''
as $$
declare
  v_role text:=custom_private.request_role();
  v_actor uuid:=custom_private.request_uid();
  v_dup boolean;
  v_count integer;
  v_subtotal_cents bigint;
  v_freight_cents bigint;
  v_discount_cents bigint;
  v_total_cents bigint;
  v_allocated jsonb;
  v_invoice_id uuid;
  v_line jsonb;
  v_material factory_private.materials%rowtype;
  v_quantity numeric;
  v_price numeric;
  v_amount numeric;
  v_landed numeric;
  v_old_value numeric;
  v_new_quantity numeric;
  v_unit_cost numeric;
  v_movement_id uuid;
  v_doc jsonb;
  v_doc_path text;
  v_doc_name text;
  v_doc_mime text;
  v_doc_size bigint;
  v_doc_count integer;
  v_kind_category text;
  v_supplier text;
  v_bill_no text;
  v_bill_date date;
  v_cash_method text;
begin
  if v_role not in ('owner','factory_manager') or v_actor is null
     or p_request_id is null or not factory_private.order_scope_allowed(p_order_id,'write') then
    raise exception using errcode='42501',message='factory_forbidden';
  end if;
  if p_document_kind not in ('板材单','五金单')
     or jsonb_typeof(coalesce(p_lines,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_documents,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_lines,'[]'::jsonb)) not between 1 and 200
     or jsonb_array_length(coalesce(p_documents,'[]'::jsonb)) not between 1 and 20
     or coalesce(p_freight,0)<0 or coalesce(p_discount,0)<0 then
    raise exception using errcode='22023',message='factory_purchase_invalid';
  end if;
  v_kind_category:=case when p_document_kind='五金单' then '五金' else '板材' end;
  v_supplier:=left(btrim(coalesce(p_supplier,'')),160);
  v_bill_no:=left(btrim(coalesce(p_bill_no,'')),100);
  v_bill_date:=coalesce(p_bill_date,current_date);
  v_cash_method:=left(coalesce(p_payment_method,'其他'),60);

  select count(*),coalesce(sum(round(x.quantity*x.unit_price*100)::bigint),0)
    into v_count,v_subtotal_cents
  from jsonb_to_recordset(p_lines) as x(
    line_no integer,material_id uuid,product text,spec text,unit text,
    quantity numeric,unit_price numeric,note text
  );
  if v_count<>jsonb_array_length(p_lines) or v_subtotal_cents<=0 then
    raise exception using errcode='22023',message='factory_purchase_invalid_lines';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_lines) as x(
      line_no integer,material_id uuid,product text,spec text,unit text,
      quantity numeric,unit_price numeric,note text
    ) left join factory_private.materials m on m.id=x.material_id
    where x.line_no is null or x.line_no<=0 or x.material_id is null
       or btrim(coalesce(x.product,''))='' or btrim(coalesce(x.unit,''))=''
       or x.quantity is null or x.quantity<=0 or x.unit_price is null or x.unit_price<0
       or m.id is null or m.unit<>x.unit
       or (p_document_kind='五金单' and m.category<>'五金')
       or (p_document_kind='板材单' and m.category not in ('板材','辅料'))
  ) or exists (
    select 1 from jsonb_to_recordset(p_lines) as x(
      line_no integer,material_id uuid,product text,spec text,unit text,
      quantity numeric,unit_price numeric,note text
    ) group by x.line_no having count(*)>1
  ) then
    raise exception using errcode='22023',message='factory_purchase_invalid_lines';
  end if;
  if round(coalesce(p_freight,0)*100)>9223372036854775807::numeric
     or round(coalesce(p_discount,0)*100)>v_subtotal_cents then
    raise exception using errcode='22023',message='factory_purchase_invalid_amount';
  end if;
  v_freight_cents:=round(coalesce(p_freight,0)*100)::bigint;
  v_discount_cents:=round(coalesce(p_discount,0)*100)::bigint;
  v_total_cents:=v_subtotal_cents+v_freight_cents-v_discount_cents;
  if v_total_cents<=0 or (p_declared_total is not null and abs(round(p_declared_total*100)::bigint-v_total_cents)>5) then
    raise exception using errcode='22023',message='factory_purchase_invoice_total_mismatch';
  end if;
  select count(*) into v_doc_count
  from jsonb_to_recordset(p_documents) as d(file_name text,storage_path text,mime_type text,file_size bigint);
  if v_doc_count<>jsonb_array_length(p_documents) or exists (
    select 1 from jsonb_to_recordset(p_documents) as d(file_name text,storage_path text,mime_type text,file_size bigint)
    where btrim(coalesce(d.file_name,''))='' or d.file_size is null or d.file_size<=0 or d.file_size>31457280
      or d.mime_type not in ('image/jpeg','image/png','image/webp','application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel')
      or not factory_private.order_storage_allowed(p_order_id,d.storage_path,'write')
  ) then
    raise exception using errcode='42501',message='factory_purchase_document_forbidden';
  end if;

  v_dup:=factory_private.claim_request('factory_receive_purchase_invoice',p_request_id,jsonb_build_object(
    'order_id',p_order_id,'kind',p_document_kind,'supplier',v_supplier,'bill_no',v_bill_no,
    'date',v_bill_date,'freight',p_freight,'discount',p_discount,'declared_total',p_declared_total,
    'lines',p_lines,'documents',p_documents,'paid',coalesce(p_paid,false),'payment_method',v_cash_method,'note',p_note
  ));
  if v_dup then return jsonb_build_object('status','ok'); end if;

  with raw as (
    select x.line_no,x.material_id,left(btrim(x.product),160) product,left(coalesce(x.spec,''),300) spec,
      left(btrim(x.unit),32) unit,x.quantity,x.unit_price,round(x.quantity*x.unit_price*100)::bigint amount_cents,
      left(coalesce(x.note,''),1000) note
    from jsonb_to_recordset(p_lines) as x(
      line_no integer,material_id uuid,product text,spec text,unit text,
      quantity numeric,unit_price numeric,note text
    )
  ), fee_base as (
    select r.*,floor(v_freight_cents::numeric*r.amount_cents/v_subtotal_cents)::bigint fee_base,
      mod(v_freight_cents::numeric*r.amount_cents,v_subtotal_cents::numeric) fee_rem
    from raw r
  ), fee_ranked as (
    select f.*,row_number() over(order by f.fee_rem desc,f.line_no) fee_rank,
      v_freight_cents-sum(f.fee_base) over() fee_left
    from fee_base f
  ), disc_base as (
    select r.*,floor(v_discount_cents::numeric*r.amount_cents/v_subtotal_cents)::bigint disc_base,
      mod(v_discount_cents::numeric*r.amount_cents,v_subtotal_cents::numeric) disc_rem
    from raw r
  ), disc_ranked as (
    select d.*,row_number() over(order by d.disc_rem desc,d.line_no) disc_rank,
      v_discount_cents-sum(d.disc_base) over() disc_left
    from disc_base d
  )
  select jsonb_agg(jsonb_build_object(
    'line_no',f.line_no,'material_id',f.material_id,'product',f.product,'spec',f.spec,'unit',f.unit,
    'quantity',f.quantity,'unit_price',f.unit_price,'amount_cents',f.amount_cents,
    'fee_cents',f.fee_base+case when f.fee_rank<=f.fee_left then 1 else 0 end,
    'discount_cents',d.disc_base+case when d.disc_rank<=d.disc_left then 1 else 0 end,'note',f.note
  ) order by f.line_no) into v_allocated
  from fee_ranked f join disc_ranked d using(line_no);

  insert into factory_private.purchase_invoices(
    order_id,document_kind,supplier,bill_no,bill_date,subtotal,freight,discount,landed_total,declared_total,status,note,created_by,request_id
  ) values(
    p_order_id,p_document_kind,v_supplier,v_bill_no,v_bill_date,v_subtotal_cents/100.0,
    v_freight_cents/100.0,v_discount_cents/100.0,v_total_cents/100.0,p_declared_total,'已核对',
    left(coalesce(p_note,''),1000),v_actor,p_request_id
  ) returning id into v_invoice_id;

  for v_line in select value from jsonb_array_elements(v_allocated) order by (value->>'line_no')::integer loop
    v_quantity:=(v_line->>'quantity')::numeric;
    v_price:=(v_line->>'unit_price')::numeric;
    v_amount:=(v_line->>'amount_cents')::numeric/100.0;
    v_landed:=((v_line->>'amount_cents')::bigint+(v_line->>'fee_cents')::bigint-(v_line->>'discount_cents')::bigint)/100.0;
    select * into v_material from factory_private.materials where id=(v_line->>'material_id')::uuid for update;
    if not found then raise exception using errcode='P0002',message='factory_material_not_found'; end if;
    v_old_value:=v_material.quantity_on_hand*v_material.moving_average_cost;
    v_new_quantity:=v_material.quantity_on_hand+v_quantity;
    v_unit_cost:=case when v_quantity=0 then 0 else v_landed/v_quantity end;
    update factory_private.materials set quantity_on_hand=v_new_quantity,
      moving_average_cost=case when v_new_quantity=0 then v_unit_cost else (v_old_value+v_landed)/v_new_quantity end,
      updated_at=now() where id=v_material.id;
    insert into factory_private.inventory_movements(
      movement_date,movement_type,material_id,quantity,unit_price,amount,unit_cost_snapshot,
      supplier_source,order_id,purpose,handled_by,note,recorded_by,request_id
    ) values(
      v_bill_date,'入库',v_material.id,v_quantity,v_unit_cost,v_landed,v_unit_cost,
      v_supplier||case when v_bill_no<>'' then ' · 单号 '||v_bill_no else '' end,p_order_id,
      '采购入库 · '||p_document_kind,'',left('票面金额 '||to_char(v_amount,'FM999999999990.00')||'；运费分摊 '||to_char((v_line->>'fee_cents')::bigint/100.0,'FM999999999990.00')||'；折让分摊 '||to_char((v_line->>'discount_cents')::bigint/100.0,'FM999999999990.00')||case when coalesce(v_line->>'note','')<>'' then '；'||(v_line->>'note') else '' end,1000),
      v_actor,gen_random_uuid()
    ) returning id into v_movement_id;
    insert into factory_private.purchase_invoice_lines(
      invoice_id,line_no,material_id,product_snapshot,spec_snapshot,unit_snapshot,quantity,
      unit_price,amount,landed_amount,inventory_movement_id,note
    ) values(
      v_invoice_id,(v_line->>'line_no')::integer,v_material.id,v_line->>'product',coalesce(v_line->>'spec',''),v_line->>'unit',
      v_quantity,v_price,v_amount,v_landed,v_movement_id,coalesce(v_line->>'note','')
    );
  end loop;

  for v_doc in select value from jsonb_array_elements(p_documents) loop
    v_doc_name:=left(v_doc->>'file_name',255);v_doc_path:=v_doc->>'storage_path';
    v_doc_mime:=v_doc->>'mime_type';v_doc_size:=(v_doc->>'file_size')::bigint;
    insert into factory_private.order_documents(
      order_id,document_kind,file_name,storage_path,mime_type,file_size,version_label,note,confirmed,
      created_by,request_id,purchase_invoice_id
    ) values(
      p_order_id,p_document_kind,v_doc_name,v_doc_path,v_doc_mime,v_doc_size,left(v_bill_no,60),
      left('采购单 '||p_document_kind||' · '||v_supplier||case when v_bill_no<>'' then ' · '||v_bill_no else '' end||' · '||v_bill_date||case when coalesce(p_note,'')<>'' then ' · '||p_note else '' end,1000),
      true,v_actor,gen_random_uuid(),v_invoice_id
    );
  end loop;

  if coalesce(p_paid,false) then
    insert into factory_private.order_cash_entries(order_id,entry_kind,entry_date,amount,method,counterparty,note,created_by,request_id)
    values(p_order_id,'付款',v_bill_date,v_total_cents/100.0,v_cash_method,v_supplier,
      left('采购付款 · '||p_document_kind||case when v_bill_no<>'' then ' · '||v_bill_no else '' end||'；只记现金流水，不计订单成本。',1000),v_actor,p_request_id);
  end if;
  return jsonb_build_object('status','ok');
end $$;
alter function api.factory_receive_purchase_invoice(uuid,text,text,text,date,numeric,numeric,numeric,jsonb,jsonb,boolean,text,text,uuid) owner to anju_custom_executor;
revoke all on function api.factory_receive_purchase_invoice(uuid,text,text,text,date,numeric,numeric,numeric,jsonb,jsonb,boolean,text,text,uuid) from public,anon;
grant execute on function api.factory_receive_purchase_invoice(uuid,text,text,text,date,numeric,numeric,numeric,jsonb,jsonb,boolean,text,text,uuid) to authenticated;

create or replace function api.owner_factory_purchase_invoices()
returns table(id uuid,order_id uuid,document_kind text,supplier text,bill_no text,bill_date date,subtotal numeric,freight numeric,discount numeric,landed_total numeric,status text,note text,lines jsonb,documents jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role()<>'owner' then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select i.id,i.order_id,i.document_kind,i.supplier,i.bill_no,i.bill_date,i.subtotal,i.freight,i.discount,i.landed_total,i.status,i.note,
    coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'line_no',l.line_no,'material_id',l.material_id,'product',l.product_snapshot,'spec',l.spec_snapshot,'unit',l.unit_snapshot,'quantity',l.quantity,'unit_price',l.unit_price,'amount',l.amount,'landed_amount',l.landed_amount,'note',l.note) order by l.line_no) from factory_private.purchase_invoice_lines l where l.invoice_id=i.id),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('name',d.file_name,'path',d.storage_path,'kind',d.document_kind) order by d.created_at) from factory_private.order_documents d where d.purchase_invoice_id=i.id),'[]'::jsonb),i.created_at
  from factory_private.purchase_invoices i order by i.bill_date desc,i.created_at desc;
end $$;

create or replace function api.factory_purchase_invoices_safe()
returns table(id uuid,order_id uuid,document_kind text,supplier text,bill_no text,bill_date date,status text,note text,lines jsonb,documents jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select i.id,i.order_id,i.document_kind,i.supplier,i.bill_no,i.bill_date,i.status,i.note,
    coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'line_no',l.line_no,'material_id',l.material_id,'product',l.product_snapshot,'spec',l.spec_snapshot,'unit',l.unit_snapshot,'quantity',l.quantity,'note',l.note) order by l.line_no) from factory_private.purchase_invoice_lines l where l.invoice_id=i.id),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('name',d.file_name,'path',d.storage_path,'kind',d.document_kind) order by d.created_at) from factory_private.order_documents d where d.purchase_invoice_id=i.id),'[]'::jsonb),i.created_at
  from factory_private.purchase_invoices i order by i.bill_date desc,i.created_at desc;
end $$;

alter function api.owner_factory_purchase_invoices() owner to anju_custom_executor;
alter function api.factory_purchase_invoices_safe() owner to anju_custom_executor;
revoke all on function api.owner_factory_purchase_invoices() from public,anon;
revoke all on function api.factory_purchase_invoices_safe() from public,anon;
grant execute on function api.owner_factory_purchase_invoices() to authenticated;
grant execute on function api.factory_purchase_invoices_safe() to authenticated;

-- The authenticated API views use this security-definer identity helper in their predicates.
grant execute on function custom_private.request_uid() to authenticated;
grant execute on function custom_private.request_role() to authenticated;

-- Supplier invoices are confidential documents; only the owner may read or sign them.
create or replace function factory_private.order_storage_allowed(p_order_id uuid,p_name text,p_action text)
returns boolean
language plpgsql stable security definer set search_path=''
as $$
declare p text[]; v_order uuid; v_role text:=custom_private.request_role();
begin
  if p_name is null or p_name like '%..%' or p_action is null or p_action not in ('read','write')
     or not factory_private.order_scope_allowed(p_order_id,case when p_action='write' then 'progress' else 'read' end) then return false; end if;
  p:=string_to_array(p_name,'/');
  if array_length(p,1)<>5 or p[1]<>'factory' or p[2] !~* '^[0-9a-f-]{36}$'
     or p[3] not in ('图纸','板材单','五金单','合同','变更单','其他资料','现场照片')
     or p[4] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or length(p[5])>180 then return false; end if;
  begin v_order:=p[2]::uuid; exception when others then return false; end;
  if v_order<>p_order_id then return false; end if;
  if p_action='write' then return v_role in ('owner','factory_manager','foreman') and factory_private.order_scope_allowed(p_order_id,'progress'); end if;
  if v_role<>'owner' and exists(
    select 1 from factory_private.order_documents d where d.order_id=p_order_id
      and d.storage_path=p_name and d.purchase_invoice_id is not null
  ) then return false; end if;
  return true;
end $$;
alter function factory_private.order_storage_allowed(uuid,text,text) owner to anju_custom_executor;
revoke all on function factory_private.order_storage_allowed(uuid,text,text) from public,anon;
grant execute on function factory_private.order_storage_allowed(uuid,text,text) to authenticated;

create or replace function api.factory_order_dossier(p_order_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare v_role text:=custom_private.request_role(); v_costs jsonb; v_cash jsonb; v_outsource jsonb; v_docs jsonb; v_config jsonb; v_notes jsonb;
begin
  if not factory_private.order_scope_allowed(p_order_id,'read') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.material_kind,x.material_name),'[]'::jsonb) into v_config
    from factory_private.order_material_configs x where x.order_id=p_order_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.document_kind,'name',x.file_name,'path',x.storage_path,'mime',x.mime_type,'version',x.version_label,'note',x.note,'confirmed',x.confirmed,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into v_docs
    from factory_private.order_documents x where x.order_id=p_order_id and (v_role='owner' or x.purchase_invoice_id is null);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_notes from factory_private.order_site_notes x where x.order_id=p_order_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'process',x.process_name,'supplier',x.supplier,'planned_date',x.planned_date,'received_date',x.received_date,'status',x.status,'quality_result',x.quality_result,'note',x.note,'actual_cost',case when v_role='owner' then x.actual_cost else null end,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into v_outsource from factory_private.outsource_jobs x where x.order_id=p_order_id;
  if v_role='owner' then
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.entry_kind,'date',x.entry_date,'amount',x.amount,'method',x.method,'counterparty',x.counterparty,'note',x.note) order by x.entry_date desc),'[]'::jsonb) into v_cash from factory_private.order_cash_entries x where x.order_id=p_order_id;
    select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'category',x.cost_category,'amount',x.amount,'source',x.source_type,'note',x.note,'created_at',x.created_at) order by x.created_at),'[]'::jsonb) into v_costs from factory_private.order_cost_entries x where x.order_id=p_order_id;
  else v_cash:='[]'::jsonb; v_costs:='[]'::jsonb; end if;
  return jsonb_build_object('material_configs',v_config,'documents',v_docs,'site_notes',v_notes,'outsource',v_outsource,'cash_entries',v_cash,'cost_entries',v_costs);
end $$;
alter function api.factory_order_dossier(uuid) owner to anju_custom_executor;
revoke all on function api.factory_order_dossier(uuid) from public,anon;
grant execute on function api.factory_order_dossier(uuid) to authenticated;

create or replace function api.factory_purchase_invoices_safe()
returns table(id uuid,order_id uuid,document_kind text,supplier text,bill_no text,bill_date date,status text,note text,lines jsonb,documents jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
  if custom_private.request_role() not in ('owner','factory_manager') then raise exception using errcode='42501',message='factory_forbidden'; end if;
  return query select i.id,i.order_id,i.document_kind,i.supplier,i.bill_no,i.bill_date,i.status,i.note,
    coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'line_no',l.line_no,'material_id',l.material_id,'product',l.product_snapshot,'spec',l.spec_snapshot,'unit',l.unit_snapshot,'quantity',l.quantity,'note',l.note) order by l.line_no) from factory_private.purchase_invoice_lines l where l.invoice_id=i.id),'[]'::jsonb),
    '[]'::jsonb,i.created_at
  from factory_private.purchase_invoices i order by i.bill_date desc,i.created_at desc;
end $$;
alter function api.factory_purchase_invoices_safe() owner to anju_custom_executor;
revoke all on function api.factory_purchase_invoices_safe() from public,anon;
grant execute on function api.factory_purchase_invoices_safe() to authenticated;

revoke create on schema factory_private from anju_custom_executor;
notify pgrst,'reload schema';
commit;
