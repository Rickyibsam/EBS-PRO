-- Atomic draft creation for GRNs and deliveries, plus a database invariant
-- preventing purchase receipts from exceeding the ordered base quantity.

do $$
begin
  if exists(
    select 1 from public.purchase_order_lines
    where coalesce(received_base_quantity,0)>quantity*conversion_to_base+0.000001
  ) then
    raise exception 'Cannot add received quantity guard: existing purchase order lines exceed ordered quantity';
  end if;
end
$$;

alter table public.purchase_order_lines
  add constraint purchase_order_lines_received_not_over_ordered
  check (coalesce(received_base_quantity,0)<=quantity*conversion_to_base+0.000001);

create or replace function public.create_goods_receipt_draft(
  p_tenant_id uuid,
  p_purchase_order_id uuid,
  p_warehouse_id uuid,
  p_received_date date,
  p_supplier_invoice_no text,
  p_notes text,
  p_lines jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,public,private,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_number text;
  v_grn_id uuid;
  v_po record;
  v_line record;
  v_requested integer;
  v_inserted integer:=0;
  v_role_allowed boolean;
  v_is_owner_admin boolean;
  v_has_override boolean;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_role_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','purchase','warehouse']);
  v_is_owner_admin:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
  select exists(select 1 from public.tenant_user_module_permissions p
    where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key='purchase_supplier')
    into v_has_override;
  if not v_role_allowed then
    if not private.module_permission_grant_internal(p_tenant_id,'purchase_supplier','create') then
      raise exception 'Goods receipt creation permission required' using errcode='42501';
    end if;
  elsif not v_is_owner_admin and v_has_override
        and not private.module_permission_grant_internal(p_tenant_id,'purchase_supplier','create') then
    raise exception 'Goods receipt creation is disabled for this user' using errcode='42501';
  end if;

  select po.id,po.branch_id,po.status into v_po
  from public.purchase_orders po
  where po.id=p_purchase_order_id and po.tenant_id=p_tenant_id
  for update;
  if not found or v_po.status not in ('approved','part_received') then
    raise exception 'Select an approved or partially received purchase order';
  end if;
  if p_warehouse_id is null or not exists(
    select 1 from public.warehouses w
    where w.id=p_warehouse_id and w.tenant_id=p_tenant_id and w.is_active
      and w.branch_id=v_po.branch_id
  ) then
    raise exception 'GRN warehouse must be active and belong to the purchase order branch';
  end if;
  if p_received_date is null then raise exception 'Goods receipt date is required'; end if;
  if p_supplier_invoice_no is not null and length(p_supplier_invoice_no)>120 then
    raise exception 'Supplier invoice number is too long';
  end if;
  if p_notes is not null and length(p_notes)>2000 then raise exception 'GRN notes cannot exceed 2000 characters'; end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Goods receipt lines must be a JSON array';
  end if;
  v_requested:=jsonb_array_length(p_lines);
  if v_requested<1 or v_requested>100 then raise exception 'GRN must contain between 1 and 100 lines'; end if;
  if (select count(distinct purchase_order_line_id)
      from jsonb_to_recordset(p_lines) as x(purchase_order_line_id uuid,quantity numeric,accepted_quantity numeric,rejected_quantity numeric,unit_cost numeric,batch_number text,manufactured_date date,expiry_date date))<>v_requested then
    raise exception 'GRN contains duplicate or invalid purchase order line references';
  end if;

  v_number:=public.next_document_number(p_tenant_id,'grn');
  insert into public.goods_receipts(
    tenant_id,purchase_order_id,warehouse_id,grn_number,received_date,
    supplier_invoice_no,status,notes,received_by
  ) values (
    p_tenant_id,p_purchase_order_id,p_warehouse_id,v_number,p_received_date,
    nullif(trim(p_supplier_invoice_no),''),'draft',nullif(trim(p_notes),''),v_user
  ) returning id into v_grn_id;

  for v_line in
    select * from jsonb_to_recordset(p_lines) as x(
      purchase_order_line_id uuid,quantity numeric,accepted_quantity numeric,
      rejected_quantity numeric,unit_cost numeric,batch_number text,
      manufactured_date date,expiry_date date
    )
  loop
    if v_line.purchase_order_line_id is null or v_line.quantity is null or v_line.quantity<=0
       or v_line.accepted_quantity is null or v_line.accepted_quantity<0
       or v_line.rejected_quantity is null or v_line.rejected_quantity<0
       or v_line.accepted_quantity+v_line.rejected_quantity<=0
       or v_line.accepted_quantity+v_line.rejected_quantity>v_line.quantity
       or v_line.unit_cost is null or v_line.unit_cost<0 then
      raise exception 'GRN line quantities and unit cost are invalid';
    end if;

    select pol.product_id,pol.unit_id,pol.quantity,pol.conversion_to_base,
           coalesce(pol.received_base_quantity,0) received_base_quantity,
           p.track_batch,p.track_expiry,p.is_active
    into v_po
    from public.purchase_order_lines pol
    join public.products p on p.id=pol.product_id and p.tenant_id=pol.tenant_id
    where pol.id=v_line.purchase_order_line_id
      and pol.tenant_id=p_tenant_id and pol.purchase_order_id=p_purchase_order_id
    for update of pol;
    if not found or not v_po.is_active then
      raise exception 'A GRN line does not match an active product on this purchase order';
    end if;
    if v_line.accepted_quantity*v_po.conversion_to_base>
       v_po.quantity*v_po.conversion_to_base-v_po.received_base_quantity+0.000001 then
      raise exception 'Accepted quantity exceeds the remaining purchase order quantity';
    end if;
    if v_line.accepted_quantity>0 and v_po.track_batch
       and nullif(btrim(v_line.batch_number),'') is null then
      raise exception 'Batch number is required for this batch-tracked product';
    end if;
    if v_line.accepted_quantity>0 and v_po.track_expiry and v_line.expiry_date is null then
      raise exception 'Expiry date is required for this expiry-tracked product';
    end if;
    if v_line.expiry_date is not null and v_line.expiry_date<current_date then
      raise exception 'Expired stock cannot be received';
    end if;
    if v_line.manufactured_date is not null and v_line.expiry_date is not null
       and v_line.manufactured_date>v_line.expiry_date then
      raise exception 'Manufacturing date cannot be later than expiry date';
    end if;

    insert into public.goods_receipt_lines(
      tenant_id,goods_receipt_id,purchase_order_line_id,product_id,unit_id,
      quantity,conversion_to_base,accepted_quantity,rejected_quantity,unit_cost,
      batch_number,manufactured_date,expiry_date
    ) values (
      p_tenant_id,v_grn_id,v_line.purchase_order_line_id,v_po.product_id,v_po.unit_id,
      v_line.quantity,v_po.conversion_to_base,v_line.accepted_quantity,v_line.rejected_quantity,
      v_line.unit_cost,nullif(btrim(v_line.batch_number),''),v_line.manufactured_date,v_line.expiry_date
    );
    v_inserted:=v_inserted+1;
  end loop;

  return jsonb_build_object('success',true,'goods_receipt_id',v_grn_id,
    'grn_number',v_number,'line_count',v_inserted,'status','draft');
end
$function$;

revoke all on function public.create_goods_receipt_draft(uuid,uuid,uuid,date,text,text,jsonb) from public,anon;
grant execute on function public.create_goods_receipt_draft(uuid,uuid,uuid,date,text,text,jsonb) to authenticated;

create or replace function public.create_delivery_draft(
  p_tenant_id uuid,
  p_sales_order_id uuid,
  p_warehouse_id uuid,
  p_delivery_date date,
  p_driver_name text,
  p_vehicle_number text,
  p_notes text,
  p_route_id uuid,
  p_delivery_man_employee_id uuid,
  p_lines jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,public,private,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_number text;
  v_delivery_id uuid;
  v_order record;
  v_line record;
  v_order_line record;
  v_requested integer;
  v_inserted integer:=0;
  v_reserved numeric;
  v_ordered_base numeric;
  v_role_allowed boolean;
  v_is_owner_admin boolean;
  v_has_override boolean;
begin
  if v_user is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_role_allowed:=public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse']);
  v_is_owner_admin:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
  select exists(select 1 from public.tenant_user_module_permissions p
    where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key='distribution_delivery')
    into v_has_override;
  if not v_role_allowed then
    if not private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','create') then
      raise exception 'Delivery creation permission required' using errcode='42501';
    end if;
  elsif not v_is_owner_admin and v_has_override
        and not private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','create') then
    raise exception 'Delivery creation is disabled for this user' using errcode='42501';
  end if;

  select so.id,so.branch_id,so.status into v_order
  from public.sales_orders so
  where so.id=p_sales_order_id and so.tenant_id=p_tenant_id
  for update;
  if not found or v_order.status not in ('approved','allocated') then
    raise exception 'Select an approved or allocated sales order';
  end if;
  if p_warehouse_id is null or not exists(
    select 1 from public.warehouses w where w.id=p_warehouse_id
      and w.tenant_id=p_tenant_id and w.is_active and w.branch_id=v_order.branch_id
  ) then
    raise exception 'Delivery warehouse must be active and belong to the sales order branch';
  end if;
  if p_delivery_date is null then raise exception 'Delivery date is required'; end if;
  if p_delivery_man_employee_id is not null and not exists(
    select 1 from public.employees e where e.id=p_delivery_man_employee_id
      and e.tenant_id=p_tenant_id and e.employment_status='active'
  ) then raise exception 'Selected delivery man must be an active employee'; end if;
  if p_route_id is not null and not exists(
    select 1 from public.sales_routes r where r.id=p_route_id
      and r.tenant_id=p_tenant_id and r.is_active
  ) then raise exception 'Selected route must be active in this company'; end if;
  if p_driver_name is not null and length(p_driver_name)>160 then raise exception 'Driver name is too long'; end if;
  if p_vehicle_number is not null and length(p_vehicle_number)>80 then raise exception 'Vehicle number is too long'; end if;
  if p_notes is not null and length(p_notes)>2000 then raise exception 'Delivery notes cannot exceed 2000 characters'; end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Delivery lines must be a JSON array';
  end if;
  v_requested:=jsonb_array_length(p_lines);
  if v_requested<1 or v_requested>100 then raise exception 'Delivery must contain between 1 and 100 lines'; end if;
  if (select count(distinct sales_order_line_id)
      from jsonb_to_recordset(p_lines) as x(sales_order_line_id uuid,quantity_base numeric))<>v_requested then
    raise exception 'Delivery contains duplicate or invalid sales order line references';
  end if;

  v_number:=public.next_document_number(p_tenant_id,'delivery');
  insert into public.deliveries(
    tenant_id,sales_order_id,warehouse_id,delivery_number,delivery_date,
    driver_name,vehicle_number,status,notes,route_id,delivery_man_employee_id
  ) values (
    p_tenant_id,p_sales_order_id,p_warehouse_id,v_number,p_delivery_date,
    nullif(trim(p_driver_name),''),nullif(trim(p_vehicle_number),''),'pending',
    nullif(trim(p_notes),''),p_route_id,p_delivery_man_employee_id
  ) returning id into v_delivery_id;

  for v_line in
    select * from jsonb_to_recordset(p_lines) as x(sales_order_line_id uuid,quantity_base numeric)
  loop
    if v_line.sales_order_line_id is null or v_line.quantity_base is null or v_line.quantity_base<=0 then
      raise exception 'Delivery line quantity must be positive';
    end if;
    select sol.id,sol.product_id,sol.quantity,sol.conversion_to_base,p.is_active
    into v_order_line
    from public.sales_order_lines sol
    join public.products p on p.id=sol.product_id and p.tenant_id=sol.tenant_id
    where sol.id=v_line.sales_order_line_id and sol.tenant_id=p_tenant_id
      and sol.sales_order_id=p_sales_order_id
    for update of sol;
    if not found or not v_order_line.is_active then
      raise exception 'A delivery line does not match an active product on this sales order';
    end if;
    v_ordered_base:=v_order_line.quantity*v_order_line.conversion_to_base;
    select coalesce(sum(case
      when d.status='pending' then dl.quantity_base
      when d.status='delivered' then dl.delivered_quantity_base
      else dl.picked_quantity_base
    end),0) into v_reserved
    from public.delivery_lines dl
    join public.deliveries d on d.id=dl.delivery_id and d.tenant_id=dl.tenant_id
    where dl.tenant_id=p_tenant_id and dl.sales_order_line_id=v_order_line.id
      and d.sales_order_id=p_sales_order_id
      and d.status in ('pending','picked','dispatched','delivered');
    if v_line.quantity_base>v_ordered_base-v_reserved+0.000001 then
      raise exception 'Delivery quantity exceeds the remaining sales order quantity for product %',v_order_line.product_id;
    end if;

    insert into public.delivery_lines(
      tenant_id,delivery_id,sales_order_line_id,product_id,
      quantity_base,picked_quantity_base,delivered_quantity_base
    ) values (
      p_tenant_id,v_delivery_id,v_order_line.id,v_order_line.product_id,
      v_line.quantity_base,0,0
    );
    v_inserted:=v_inserted+1;
  end loop;

  return jsonb_build_object('success',true,'delivery_id',v_delivery_id,
    'delivery_number',v_number,'line_count',v_inserted,'status','pending');
end
$function$;

revoke all on function public.create_delivery_draft(uuid,uuid,uuid,date,text,text,text,uuid,uuid,jsonb) from public,anon;
grant execute on function public.create_delivery_draft(uuid,uuid,uuid,date,text,text,text,uuid,uuid,jsonb) to authenticated;
