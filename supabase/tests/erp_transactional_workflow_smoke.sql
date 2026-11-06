-- EBS PRO transactional database smoke test.
-- Run only in the EBS-PRO Supabase SQL Editor.
-- All fixture rows are created inside one transaction and rolled back at the end.
-- No production business data is retained.

begin;

do $smoke$
declare
  v_user uuid;
  v_booker_user uuid;
  v_tenant_a uuid := gen_random_uuid();
  v_tenant_b uuid := gen_random_uuid();
  v_branch_a uuid := gen_random_uuid();
  v_branch_b uuid := gen_random_uuid();
  v_account_debit uuid := gen_random_uuid();
  v_account_credit uuid := gen_random_uuid();
  v_journal_ok uuid := gen_random_uuid();
  v_journal_bad uuid := gen_random_uuid();
  v_route uuid := gen_random_uuid();
  v_employee uuid := gen_random_uuid();
  v_customer uuid := gen_random_uuid();
  v_unit uuid := gen_random_uuid();
  v_product uuid := gen_random_uuid();
  v_price_list uuid := gen_random_uuid();
  v_order_request uuid := gen_random_uuid();
  v_order_first uuid;
  v_order_retry uuid;
  v_supplier uuid := gen_random_uuid();
  v_purchase_order uuid := gen_random_uuid();
  v_purchase_order_line uuid := gen_random_uuid();
  v_grn uuid := gen_random_uuid();
  v_grn_line uuid := gen_random_uuid();
  v_purchase_invoice uuid;
  v_debit_note uuid;
  v_invoice_result jsonb;
  v_debit_result jsonb;
  v_inventory_account uuid := gen_random_uuid();
  v_grni_account uuid := gen_random_uuid();
  v_tax_account uuid := gen_random_uuid();
  v_ap_account uuid := gen_random_uuid();
  v_cogs_account uuid := gen_random_uuid();
  v_ar_account uuid := gen_random_uuid();
  v_sales_tax_account uuid := gen_random_uuid();
  v_delivery_result jsonb;
  v_delivery_id uuid;
  v_delivery_line uuid;
  v_dispatch_result jsonb;
  v_complete_result jsonb;
  v_sales_invoice_id uuid;
  v_rejected boolean := false;
begin
  select user_id into v_user
  from public.tenant_memberships
  where role='owner' and is_active
  order by created_at
  limit 1;
  if v_user is null then raise exception 'Smoke test requires an active owner membership'; end if;
  select user_id into v_booker_user
  from public.tenant_memberships
  where role='admin' and is_active
  order by created_at
  limit 1;
  if v_booker_user is null or v_booker_user=v_user then
    raise exception 'Smoke test requires a second active user for the Order Booker workflow';
  end if;
  perform set_config('request.jwt.claim.sub',v_user::text,true);

  insert into public.organizations(id,name,slug) values
    (v_tenant_a,'EBS Transaction Test A','ebs-tx-test-a-'||replace(v_tenant_a::text,'-','')),
    (v_tenant_b,'EBS Transaction Test B','ebs-tx-test-b-'||replace(v_tenant_b::text,'-',''));
  insert into public.tenant_memberships(tenant_id,user_id,role,is_active)
  values(v_tenant_a,v_user,'owner',true),(v_tenant_a,v_booker_user,'order_booker',true);

  insert into public.branches(id,tenant_id,name,code)
  values(v_branch_a,v_tenant_a,'Test Branch A','TX-A'),
        (v_branch_b,v_tenant_b,'Test Branch B','TX-B');

  -- Cross-tenant branch reference must be rejected by the composite FK.
  begin
    insert into public.warehouses(tenant_id,branch_id,name,code)
    values(v_tenant_a,v_branch_b,'Invalid Cross Tenant Warehouse','TX-WH-X');
  exception when foreign_key_violation then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'FAIL: cross-tenant branch reference was accepted'; end if;

  -- Booker PWA: create a route, assigned employee, customer, warehouse, product and price.
  insert into public.employees(id,tenant_id,user_id,branch_id,employee_code,full_name,job_title)
  values(v_employee,v_tenant_a,v_booker_user,v_branch_a,'TX-BOOKER','Smoke Test Booker','Order Booker');
  insert into public.sales_routes(id,tenant_id,branch_id,route_code,name)
  values(v_route,v_tenant_a,v_branch_a,'TX-ROUTE','Smoke Test Route');
  insert into public.route_assignments(tenant_id,route_id,employee_id,assigned_from)
  values(v_tenant_a,v_route,v_employee,current_date);
  insert into public.parties(tenant_id,party_code,party_type,name)
  values(v_tenant_a,'TX-CUST','customer','Smoke Test Customer') returning id into v_customer;
  insert into public.route_customers(tenant_id,route_id,customer_id)
  values(v_tenant_a,v_route,v_customer);
  insert into public.warehouses(tenant_id,branch_id,name,code,is_default)
  values(v_tenant_a,v_branch_a,'Smoke Test Warehouse','TX-WH',true);
  insert into public.units_of_measure(id,tenant_id,name,symbol,unit_type,decimal_places)
  values(v_unit,v_tenant_a,'Smoke Test Unit','EA','quantity',0);
  insert into public.products(tenant_id,sku,name,base_unit_id,sales_tax_rate,sale_price)
  values(v_tenant_a,'TX-SKU','Smoke Test Product',v_unit,17,50) returning id into v_product;
  insert into public.product_units(tenant_id,product_id,unit_id,conversion_to_base,is_sales_unit)
  values(v_tenant_a,v_product,v_unit,1,true);
  insert into public.price_lists(tenant_id,name,price_type,is_default)
  values(v_tenant_a,'Smoke Test Price List','retail',true) returning id into v_price_list;
  insert into public.product_prices(tenant_id,price_list_id,product_id,unit_id,price,min_quantity)
  values(v_tenant_a,v_price_list,v_product,v_unit,50,1);

  -- Booker order uses server-side price/tax and a stable idempotency key.
  perform set_config('request.jwt.claim.sub',v_booker_user::text,true);
  v_order_first:=public.create_order_booker_order(
    v_tenant_a,v_route,v_customer,v_order_request,current_date+1,'Smoke test Booker order',
    jsonb_build_array(jsonb_build_object('product_id',v_product,'unit_id',v_unit,'quantity',2))
  );
  if not exists(select 1 from public.sales_orders where id=v_order_first and tenant_id=v_tenant_a
    and subtotal=100 and tax_total=17 and grand_total=117) then
    raise exception 'FAIL: Booker order totals were not calculated by the server';
  end if;
  update public.sales_routes set is_active=false
  where tenant_id=v_tenant_a and id=v_route;
  v_order_retry:=public.create_order_booker_order(
    v_tenant_a,v_route,v_customer,v_order_request,current_date+1,'Retry after route change',
    jsonb_build_array(jsonb_build_object('product_id',v_product,'unit_id',v_unit,'quantity',2))
  );
  if v_order_retry<>v_order_first then
    raise exception 'FAIL: Booker idempotent retry returned a different order';
  end if;
  if (select count(*) from public.sales_orders where tenant_id=v_tenant_a and client_request_id=v_order_request)<>1 then
    raise exception 'FAIL: Booker idempotent retry created duplicate orders';
  end if;

  perform set_config('request.jwt.claim.sub',v_user::text,true);
  insert into public.chart_of_accounts(id,tenant_id,account_code,account_name,account_type)
  values
    (v_account_debit,v_tenant_a,'TX-1000','Smoke Test Cash','asset'),
    (v_account_credit,v_tenant_a,'TX-4000','Smoke Test Income','income'),
    (v_inventory_account,v_tenant_a,'1200','Inventory','asset'),
    (v_grni_account,v_tenant_a,'2100','Goods Received Not Invoiced','liability'),
    (v_tax_account,v_tenant_a,'1300','Input Tax','asset'),
    (v_ap_account,v_tenant_a,'2000','Accounts Payable','liability'),
    (v_cogs_account,v_tenant_a,'5000','Cost of Goods Sold','expense'),
    (v_ar_account,v_tenant_a,'1100','Accounts Receivable','asset'),
    (v_sales_tax_account,v_tenant_a,'2200','Sales Tax Payable','liability');

  -- Purchase -> GRN -> stock ledger -> supplier invoice -> GL workflow.
  insert into public.parties(id,tenant_id,party_code,party_type,name)
  values(v_supplier,v_tenant_a,'TX-SUP','supplier','Smoke Test Supplier');
  insert into public.purchase_orders(id,tenant_id,branch_id,warehouse_id,supplier_id,po_number,status,created_by)
  values(v_purchase_order,v_tenant_a,v_branch_a,
    (select id from public.warehouses where tenant_id=v_tenant_a and code='TX-WH'),
    v_supplier,'TX-PO-001','draft',v_user);
  insert into public.purchase_order_lines(id,tenant_id,purchase_order_id,product_id,unit_id,quantity,conversion_to_base,unit_cost,tax_rate,line_total)
  values(v_purchase_order_line,v_tenant_a,v_purchase_order,v_product,v_unit,10,1,20,10,200);
  update public.purchase_orders set status='approved',approved_by=v_user
  where id=v_purchase_order and tenant_id=v_tenant_a;
  insert into public.goods_receipts(id,tenant_id,purchase_order_id,warehouse_id,grn_number,received_date,status,received_by)
  values(v_grn,v_tenant_a,v_purchase_order,
    (select id from public.warehouses where tenant_id=v_tenant_a and code='TX-WH'),
    'TX-GRN-001',current_date,'draft',v_user);
  insert into public.goods_receipt_lines(id,tenant_id,goods_receipt_id,product_id,unit_id,quantity,conversion_to_base,accepted_quantity,rejected_quantity,unit_cost,purchase_order_line_id)
  values(v_grn_line,v_tenant_a,v_grn,v_product,v_unit,5,1,5,0,20,v_purchase_order_line);
  perform public.post_goods_receipt(v_grn);
  if not exists(select 1 from public.stock_movements where tenant_id=v_tenant_a
    and reference_type='goods_receipt' and reference_id=v_grn and quantity_in=5) then
    raise exception 'FAIL: GRN did not create the expected stock movement';
  end if;
  v_invoice_result:=public.create_purchase_invoice(v_grn,'TX-SUP-INV-001',current_date,current_date+30,10,'Smoke test supplier invoice');
  v_purchase_invoice:=(v_invoice_result->>'purchase_invoice_id')::uuid;
  perform public.post_purchase_invoice(v_purchase_invoice);
  if not exists(select 1 from public.purchase_invoices where id=v_purchase_invoice and status='posted' and grand_total=110) then
    raise exception 'FAIL: supplier invoice did not post with expected total';
  end if;
  if not exists(select 1 from public.journal_entries where tenant_id=v_tenant_a
    and source_type='purchase_invoice' and source_id=v_purchase_invoice and status='posted') then
    raise exception 'FAIL: supplier invoice posting did not create a GL journal';
  end if;

  -- Purchase return must reduce stock and post the supplier/AP journal.
  v_debit_result:=public.create_purchase_debit_note(
    v_grn,
    jsonb_build_array(jsonb_build_object('goods_receipt_line_id',v_grn_line,'quantity',1)),
    'Smoke test supplier return',
    current_date
  );
  v_debit_note:=(v_debit_result->>'debit_note_id')::uuid;
  perform public.post_purchase_debit_note(v_debit_note);
  if not exists(select 1 from public.purchase_debit_notes where id=v_debit_note and status='posted') then
    raise exception 'FAIL: purchase debit note did not post';
  end if;
  if not exists(select 1 from public.stock_movements where tenant_id=v_tenant_a
    and reference_type='purchase_debit_note' and reference_id=v_debit_note and quantity_out=1) then
    raise exception 'FAIL: purchase return did not reduce stock';
  end if;
  if not exists(select 1 from public.journal_entries where tenant_id=v_tenant_a
    and source_type='purchase_return' and source_id=v_debit_note and status='posted') then
    raise exception 'FAIL: purchase return did not create a GL journal';
  end if;

  -- Sales order -> delivery allocation -> stock dispatch -> invoice/AR/revenue.
  update public.sales_orders set status='approved',approved_by=v_user
  where id=v_order_first and tenant_id=v_tenant_a;
  v_delivery_result:=public.create_delivery_for_approved_order(v_order_first,v_employee);
  v_delivery_id:=(v_delivery_result->>'delivery_id')::uuid;
  select id into v_delivery_line from public.delivery_lines
  where tenant_id=v_tenant_a and delivery_id=v_delivery_id;
  if (select warehouse_id from public.sales_orders where id=v_order_first) is distinct from
     (select warehouse_id from public.deliveries where id=v_delivery_id) then
    raise exception 'FAIL: sales order and delivery warehouse do not match';
  end if;
  if coalesce((select sum(quantity_in-quantity_out) from public.stock_movements
    where tenant_id=v_tenant_a and warehouse_id=(select warehouse_id from public.deliveries where id=v_delivery_id)
      and product_id=v_product),0)<2 then
    raise exception 'FAIL: stock fixture is short before dispatch: %',
      coalesce((select sum(quantity_in-quantity_out) from public.stock_movements
       where tenant_id=v_tenant_a and warehouse_id=(select warehouse_id from public.deliveries where id=v_delivery_id)
         and product_id=v_product),0);
  end if;
  v_dispatch_result:=public.dispatch_delivery(
    v_delivery_id,
    jsonb_build_array(jsonb_build_object('line_id',v_delivery_line,'picked_quantity_base',2))
  );
  if not exists(select 1 from public.stock_movements where tenant_id=v_tenant_a
    and reference_type='delivery' and reference_id=v_delivery_id and movement_type='sale_dispatch' and quantity_out=2) then
    raise exception 'FAIL: delivery dispatch did not issue stock';
  end if;
  v_complete_result:=public.complete_delivery(
    v_delivery_id,
    jsonb_build_array(jsonb_build_object('line_id',v_delivery_line,'delivered_quantity_base',2))
  );
  v_sales_invoice_id:=(v_complete_result->>'invoice_id')::uuid;
  if not exists(select 1 from public.sales_invoices where id=v_sales_invoice_id
    and tenant_id=v_tenant_a and status='posted' and grand_total=117) then
    raise exception 'FAIL: delivery completion did not create the expected posted invoice';
  end if;
  if not exists(select 1 from public.journal_entries where tenant_id=v_tenant_a
    and source_type='sales_invoice' and source_id=v_sales_invoice_id and status='posted') then
    raise exception 'FAIL: sales invoice did not create an AR/revenue journal';
  end if;

  -- Balanced journal must post and preserve double-entry equality.
  insert into public.journal_entries(id,tenant_id,journal_number,entry_date,narration,status,created_by)
  values(v_journal_ok,v_tenant_a,'TX-JV-OK',current_date,'Transactional smoke test balanced journal','draft',v_user);
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values
    (v_tenant_a,v_journal_ok,v_account_debit,100,0,'Balanced debit'),
    (v_tenant_a,v_journal_ok,v_account_credit,0,100,'Balanced credit');
  perform public.post_journal_entry(v_journal_ok);
  if (select status from public.journal_entries where id=v_journal_ok)<>'posted' then
    raise exception 'FAIL: balanced journal did not post';
  end if;

  -- Unbalanced journal must be rejected and remain draft.
  insert into public.journal_entries(id,tenant_id,journal_number,entry_date,narration,status,created_by)
  values(v_journal_bad,v_tenant_a,'TX-JV-BAD',current_date,'Transactional smoke test unbalanced journal','draft',v_user);
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values
    (v_tenant_a,v_journal_bad,v_account_debit,100,0,'Unbalanced debit'),
    (v_tenant_a,v_journal_bad,v_account_credit,0,90,'Unbalanced credit');

  v_rejected:=false;
  begin
    perform public.post_journal_entry(v_journal_bad);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'FAIL: unbalanced journal was accepted'; end if;
  if (select status from public.journal_entries where id=v_journal_bad)<>'draft' then
    raise exception 'FAIL: rejected journal changed state';
  end if;
end
$smoke$;

rollback;
