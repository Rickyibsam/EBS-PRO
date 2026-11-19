-- Create back-office sales and purchase orders atomically.
-- The document sequence, header and all detail lines commit or roll back together.

create or replace function public.create_backoffice_order(
  p_tenant_id uuid,
  p_document_type text,
  p_branch_id uuid,
  p_warehouse_id uuid,
  p_party_id uuid,
  p_order_date date,
  p_notes text,
  p_booker_employee_id uuid,
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
  v_order_id uuid;
  v_requested integer;
  v_inserted integer:=0;
  v_line record;
  v_conversion numeric;
  v_gross numeric;
  v_discount numeric;
  v_tax numeric;
  v_subtotal numeric:=0;
  v_discount_total numeric:=0;
  v_tax_total numeric:=0;
  v_grand_total numeric:=0;
  v_line_total numeric;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if p_document_type is null or p_document_type not in ('sales_order','purchase_order') then
    raise exception 'Unsupported order type';
  end if;
  if p_document_type='sales_order' then
    if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','sales'])
      or private.module_permission_grant_internal(p_tenant_id,'sales_customer','create')) then
      raise exception 'Sales order creation permission required' using errcode='42501';
    end if;
  else
    if not (public.has_tenant_role(p_tenant_id,array['owner','admin','manager','purchase'])
      or private.module_permission_grant_internal(p_tenant_id,'purchase_supplier','create')) then
      raise exception 'Purchase order creation permission required' using errcode='42501';
    end if;
  end if;
  if p_branch_id is null or not exists(
    select 1 from public.branches b
    where b.id=p_branch_id and b.tenant_id=p_tenant_id and b.is_active
  ) then
    raise exception 'Select an active branch in this company';
  end if;
  if p_document_type='sales_order' and p_warehouse_id is null then
    raise exception 'Select an active warehouse for the sales order';
  end if;
  if p_warehouse_id is not null and not exists(
    select 1 from public.warehouses w
    where w.id=p_warehouse_id and w.tenant_id=p_tenant_id and w.is_active
      and w.branch_id=p_branch_id
  ) then
    raise exception 'Selected warehouse must be active and belong to the selected branch';
  end if;
  if p_document_type='sales_order' then
    if not exists(select 1 from public.parties p where p.id=p_party_id and p.tenant_id=p_tenant_id
      and p.status='active' and p.party_type in ('customer','both')) then
      raise exception 'Select an active customer in this company';
    end if;
    if p_booker_employee_id is not null and not exists(
      select 1 from public.employees e where e.id=p_booker_employee_id
        and e.tenant_id=p_tenant_id and e.employment_status='active'
    ) then raise exception 'Selected Booker must be an active employee in this company'; end if;
    if p_delivery_man_employee_id is not null and not exists(
      select 1 from public.employees e where e.id=p_delivery_man_employee_id
        and e.tenant_id=p_tenant_id and e.employment_status='active'
    ) then raise exception 'Selected delivery man must be an active employee in this company'; end if;
    if p_route_id is not null and not exists(
      select 1 from public.sales_routes r where r.id=p_route_id
        and r.tenant_id=p_tenant_id and r.is_active
    ) then raise exception 'Selected sales route must be active in this company'; end if;
  else
    if not exists(select 1 from public.parties p where p.id=p_party_id and p.tenant_id=p_tenant_id
      and p.status='active' and p.party_type in ('supplier','both')) then
      raise exception 'Select an active Vendor in this company';
    end if;
  end if;
  if p_notes is not null and length(p_notes)>2000 then
    raise exception 'Order notes cannot exceed 2000 characters';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Order lines must be a JSON array';
  end if;
  v_requested:=jsonb_array_length(p_lines);
  if v_requested<1 or v_requested>100 then
    raise exception 'Order must contain between 1 and 100 lines';
  end if;

  v_number:=public.next_document_number(p_tenant_id,p_document_type);
  if p_document_type='sales_order' then
    insert into public.sales_orders(
      tenant_id,branch_id,warehouse_id,customer_id,route_id,booker_employee_id,
      delivery_man_employee_id,order_number,order_source,order_date,status,
      subtotal,tax_total,discount_total,grand_total,notes,created_by
    ) values (
      p_tenant_id,p_branch_id,p_warehouse_id,p_party_id,p_route_id,p_booker_employee_id,
      p_delivery_man_employee_id,v_number,'backoffice',now(),'draft',
      0,0,0,0,nullif(trim(p_notes),''),v_user
    ) returning id into v_order_id;
  else
    insert into public.purchase_orders(
      tenant_id,branch_id,warehouse_id,supplier_id,po_number,order_date,status,
      subtotal,tax_total,discount_total,grand_total,notes,created_by
    ) values (
      p_tenant_id,p_branch_id,p_warehouse_id,p_party_id,v_number,coalesce(p_order_date,current_date),
      'draft',0,0,0,0,nullif(trim(p_notes),''),v_user
    ) returning id into v_order_id;
  end if;

  for v_line in
    select * from jsonb_to_recordset(p_lines) as x(
      product_id uuid,unit_id uuid,quantity numeric,unit_rate numeric,
      tax_rate numeric,discount_amount numeric
    )
  loop
    if v_line.product_id is null or v_line.unit_id is null
       or v_line.quantity is null or v_line.quantity<=0 or v_line.quantity>1000000
       or v_line.unit_rate is null or v_line.unit_rate<0
       or v_line.tax_rate is null or v_line.tax_rate<0 or v_line.tax_rate>100
       or v_line.discount_amount is null or v_line.discount_amount<0 then
      raise exception 'Every order line must have valid product, unit, quantity, rate, tax and discount values';
    end if;
    select pu.conversion_to_base into v_conversion
    from public.product_units pu
    join public.products p on p.id=pu.product_id and p.tenant_id=pu.tenant_id
    where pu.tenant_id=p_tenant_id and pu.product_id=v_line.product_id
      and pu.unit_id=v_line.unit_id and p.is_active
      and case when p_document_type='sales_order' then pu.is_sales_unit else pu.is_purchase_unit end;
    if v_conversion is null or v_conversion<=0 then
      raise exception 'Selected unit is not configured for product %',v_line.product_id;
    end if;

    v_gross:=round(v_line.quantity*v_line.unit_rate,2);
    v_discount:=round(v_line.discount_amount,2);
    if v_discount>v_gross+0.005 then
      raise exception 'A line discount cannot exceed the pre-tax gross amount';
    end if;
    v_tax:=round(greatest(0,v_gross-v_discount)*v_line.tax_rate/100,2);
    v_line_total:=v_gross-v_discount+v_tax;

    if p_document_type='sales_order' then
      insert into public.sales_order_lines(
        tenant_id,sales_order_id,product_id,unit_id,quantity,conversion_to_base,
        unit_price,tax_rate,discount_amount,line_total
      ) values (
        p_tenant_id,v_order_id,v_line.product_id,v_line.unit_id,v_line.quantity,
        v_conversion,v_line.unit_rate,v_line.tax_rate,v_discount,v_line_total
      );
    else
      insert into public.purchase_order_lines(
        tenant_id,purchase_order_id,product_id,unit_id,quantity,conversion_to_base,
        unit_cost,tax_rate,discount_amount,line_total,received_base_quantity
      ) values (
        p_tenant_id,v_order_id,v_line.product_id,v_line.unit_id,v_line.quantity,
        v_conversion,v_line.unit_rate,v_line.tax_rate,v_discount,v_line_total,0
      );
    end if;

    v_subtotal:=v_subtotal+v_gross;
    v_discount_total:=v_discount_total+v_discount;
    v_tax_total:=v_tax_total+v_tax;
    v_inserted:=v_inserted+1;
  end loop;

  v_grand_total:=v_subtotal-v_discount_total+v_tax_total;
  if p_document_type='sales_order' then
    update public.sales_orders set subtotal=v_subtotal,tax_total=v_tax_total,
      discount_total=v_discount_total,grand_total=v_grand_total,updated_at=now()
    where id=v_order_id and tenant_id=p_tenant_id;
  else
    update public.purchase_orders set subtotal=v_subtotal,tax_total=v_tax_total,
      discount_total=v_discount_total,grand_total=v_grand_total,updated_at=now()
    where id=v_order_id and tenant_id=p_tenant_id;
  end if;

  return jsonb_build_object(
    'success',true,'order_id',v_order_id,'document_number',v_number,
    'line_count',v_inserted,'subtotal',v_subtotal,'discount_total',v_discount_total,
    'tax_total',v_tax_total,'grand_total',v_grand_total,'status','draft'
  );
end
$function$;

revoke all on function public.create_backoffice_order(uuid,text,uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb) from public,anon;
grant execute on function public.create_backoffice_order(uuid,text,uuid,uuid,uuid,date,text,uuid,uuid,uuid,jsonb) to authenticated;
