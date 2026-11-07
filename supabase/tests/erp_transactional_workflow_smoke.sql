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
  v_warehouse uuid;
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
  v_payroll_run uuid := gen_random_uuid();
  v_payroll_line uuid := gen_random_uuid();
  v_bad_payroll_run uuid := gen_random_uuid();
  v_bad_payroll_line uuid := gen_random_uuid();
  v_payroll_result jsonb;
  v_payment_result jsonb;
  v_payment_retry jsonb;
  v_rejected boolean := false;
  v_asset uuid := gen_random_uuid();
  v_asset_cost_account uuid := gen_random_uuid();
  v_accumulated_account uuid := gen_random_uuid();
  v_depreciation_expense_account uuid := gen_random_uuid();
  v_disposal_gain_account uuid := gen_random_uuid();
  v_disposal_loss_account uuid := gen_random_uuid();
  v_depreciation_result jsonb;
  v_depreciation_retry jsonb;
  v_disposal_result jsonb;
  v_budget uuid := gen_random_uuid();
  v_budget_company_supported boolean;
  v_budget_branch_supported boolean;
  v_backup jsonb;
  v_restore jsonb;
  v_restore_fixture_backup jsonb;
  v_restore_fixture_result jsonb;
  v_permission_rejected boolean := false;
  v_second_warehouse uuid := gen_random_uuid();
  v_stock_transfer uuid := gen_random_uuid();
  v_stock_transfer_line uuid := gen_random_uuid();
  v_stock_transfer_result jsonb;
  v_stock_take uuid;
  v_stock_take_result jsonb;
  v_attendance_result jsonb;
  v_leave_id uuid := gen_random_uuid();
  v_leave_result jsonb;
  v_signature_result jsonb;
  v_rls_rows integer := -1;
  v_report_result jsonb;
  v_module_key text;
  v_action text;
  v_van_route uuid := gen_random_uuid();
  v_van_order_request uuid := gen_random_uuid();
  v_van_order uuid;
  v_van_delivery uuid;
  v_van_line uuid;
  v_van_load_result jsonb;
  v_van_dispatch_result jsonb;
  v_van_visit_result jsonb;
  v_van_visit_retry jsonb;
  v_failed_order_request uuid := gen_random_uuid();
  v_failed_order uuid;
  v_failed_delivery uuid;
  v_failed_line uuid;
  v_failed_visit_result jsonb;
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
  select warehouse_id into v_warehouse from public.sales_orders where id=v_order_first;

  -- Direct voucher RPC must enforce custom per-user update denial, not rely on UI.
  insert into public.tenant_user_module_permissions(
    tenant_id,user_id,module_key,can_view,can_create,can_update,can_delete
  ) values(v_tenant_a,v_booker_user,'sales_customer',true,true,false,false);
  v_permission_rejected:=false;
  begin
    perform public.update_draft_voucher_lines(v_tenant_a,'sales_orders',v_order_first,'[]'::jsonb);
  exception when insufficient_privilege then
    v_permission_rejected:=true;
  end;
  if not v_permission_rejected then
    raise exception 'FAIL: direct voucher RPC bypassed custom update denial';
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
    (v_account_debit,v_tenant_a,'1000','Cash','asset'),
    (v_account_credit,v_tenant_a,'4000','Smoke Test Income','income'),
    (v_inventory_account,v_tenant_a,'1200','Inventory','asset'),
    (v_grni_account,v_tenant_a,'2100','Goods Received Not Invoiced','liability'),
    (v_tax_account,v_tenant_a,'1300','Input Tax','asset'),
    (v_ap_account,v_tenant_a,'2000','Accounts Payable','liability'),
    (v_cogs_account,v_tenant_a,'5000','Cost of Goods Sold','expense'),
    (v_ar_account,v_tenant_a,'1100','Accounts Receivable','asset'),
    (v_sales_tax_account,v_tenant_a,'2200','Sales Tax Payable','liability'),
    (gen_random_uuid(),v_tenant_a,'1010','Bank','asset'),
    (gen_random_uuid(),v_tenant_a,'5200','Salaries Expense','expense'),
    (gen_random_uuid(),v_tenant_a,'2150','Salaries Payable','liability'),
    (gen_random_uuid(),v_tenant_a,'2160','Payroll Deductions Payable','liability'),
    (v_asset_cost_account,v_tenant_a,'1500','Fixed Asset Cost','asset'),
    (v_accumulated_account,v_tenant_a,'1590','Accumulated Depreciation','asset'),
    (v_depreciation_expense_account,v_tenant_a,'5300','Depreciation Expense','expense'),
    (v_disposal_gain_account,v_tenant_a,'4900','Gain on Asset Disposal','income'),
    (v_disposal_loss_account,v_tenant_a,'5900','Loss on Asset Disposal','expense');

  -- Purchase -> GRN -> stock ledger -> supplier invoice -> GL workflow.
  insert into public.parties(id,tenant_id,party_code,party_type,name)
  values(v_supplier,v_tenant_a,'TX-SUP','supplier','Smoke Test Supplier');
  insert into public.purchase_orders(id,tenant_id,branch_id,warehouse_id,supplier_id,po_number,status,created_by)
  values(v_purchase_order,v_tenant_a,v_branch_a,
    v_warehouse,
    v_supplier,'TX-PO-001','draft',v_user);
  insert into public.purchase_order_lines(id,tenant_id,purchase_order_id,product_id,unit_id,quantity,conversion_to_base,unit_cost,tax_rate,line_total)
  values(v_purchase_order_line,v_tenant_a,v_purchase_order,v_product,v_unit,10,1,20,10,200);
  update public.purchase_orders set status='approved',approved_by=v_user
  where id=v_purchase_order and tenant_id=v_tenant_a;
  insert into public.goods_receipts(id,tenant_id,purchase_order_id,warehouse_id,grn_number,received_date,status,received_by)
  values(v_grn,v_tenant_a,v_purchase_order,
    v_warehouse,
    'TX-GRN-001',current_date,'draft',v_user);
  insert into public.goods_receipt_lines(id,tenant_id,goods_receipt_id,product_id,unit_id,quantity,conversion_to_base,accepted_quantity,rejected_quantity,unit_cost,purchase_order_line_id)
  values(v_grn_line,v_tenant_a,v_grn,v_product,v_unit,7,1,7,0,20,v_purchase_order_line);
  perform public.post_goods_receipt(v_grn);
  if not exists(select 1 from public.stock_movements where tenant_id=v_tenant_a
    and reference_type='goods_receipt' and reference_id=v_grn and quantity_in=7) then
    raise exception 'FAIL: GRN did not create the expected stock movement';
  end if;
  v_invoice_result:=public.create_purchase_invoice(v_grn,'TX-SUP-INV-001',current_date,current_date+30,10,'Smoke test supplier invoice');
  v_purchase_invoice:=(v_invoice_result->>'purchase_invoice_id')::uuid;
  perform public.post_purchase_invoice(v_purchase_invoice);
  if not exists(select 1 from public.purchase_invoices where id=v_purchase_invoice and status='posted' and grand_total=150) then
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
    raise exception 'FAIL: stock fixture is short before dispatch. order warehouse %, GRN warehouse %, movements %',
      (select warehouse_id from public.sales_orders where id=v_order_first),
      (select warehouse_id from public.goods_receipts where id=v_grn),
      (select coalesce(jsonb_agg(jsonb_build_object('warehouse',warehouse_id,'type',movement_type,'in',quantity_in,'out',quantity_out)), '[]'::jsonb)
       from public.stock_movements where tenant_id=v_tenant_a and product_id=v_product);
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


  -- Van delivery PWA: load stock, dispatch to a vehicle, record partial delivery/market return, replay once.
  insert into public.sales_routes(id,tenant_id,branch_id,route_code,name)
  values(v_van_route,v_tenant_a,v_branch_a,'TX-VAN-ROUTE','Smoke Test Van Route');
  insert into public.route_assignments(tenant_id,route_id,employee_id,assigned_from)
  values(v_tenant_a,v_van_route,v_employee,current_date);
  insert into public.route_customers(tenant_id,route_id,customer_id)
  values(v_tenant_a,v_van_route,v_customer);
  perform set_config('request.jwt.claim.sub',v_booker_user::text,true);
  v_van_order:=public.create_order_booker_order(
    v_tenant_a,v_van_route,v_customer,v_van_order_request,current_date+1,'Smoke test van delivery',
    jsonb_build_array(jsonb_build_object('product_id',v_product,'unit_id',v_unit,'quantity',2))
  );
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  update public.sales_orders set status='approved',approved_by=v_user
  where id=v_van_order and tenant_id=v_tenant_a;
  v_van_delivery:=(public.create_delivery_for_approved_order(v_van_order,v_employee)->>'delivery_id')::uuid;
  select id into v_van_line from public.delivery_lines
  where tenant_id=v_tenant_a and delivery_id=v_van_delivery;
  v_van_load_result:=public.record_van_stock_transfer(
    v_tenant_a,v_warehouse,'TX-VAN-01',v_employee,v_product,'load',2,
    null,null,'TX-VAN-LOAD-0001','Rollback-only van load'
  );
  if coalesce((v_van_load_result->>'replayed')::boolean,true) is not false then
    raise exception 'FAIL: first van stock load was unexpectedly replayed';
  end if;
  v_van_dispatch_result:=public.dispatch_van_delivery(
    v_van_delivery,'TX-VAN-01',
    jsonb_build_array(jsonb_build_object('line_id',v_van_line,'picked_quantity_base',2))
  );
  if coalesce((v_van_dispatch_result->>'success')::boolean,false) is not true then
    raise exception 'FAIL: van delivery did not dispatch';
  end if;
  v_van_visit_result:=public.record_van_delivery_visit(
    v_van_delivery,'short_delivered',
    jsonb_build_array(jsonb_build_object(
      'delivery_line_id',v_van_line,'delivered_quantity_base',2,
      'market_return_quantity_base',1,'return_batch_number',null,'return_expiry_date',null
    )),
    'One unit sold, one unit returned to van',
    'TX-VAN-VISIT-0001'
  );
  if coalesce((v_van_visit_result->>'success')::boolean,false) is not true
     or coalesce((v_van_visit_result->>'sold_quantity')::numeric,0)<>1
     or coalesce((v_van_visit_result->>'returned_quantity')::numeric,0)<>1 then
    raise exception 'FAIL: partial van delivery and market return did not reconcile: %',v_van_visit_result;
  end if;
  v_van_visit_retry:=public.record_van_delivery_visit(
    v_van_delivery,'short_delivered',
    jsonb_build_array(jsonb_build_object(
      'delivery_line_id',v_van_line,'delivered_quantity_base',2,
      'market_return_quantity_base',1,'return_batch_number',null,'return_expiry_date',null
    )),
    'Retry of the same van visit',
    'TX-VAN-VISIT-0001'
  );
  if coalesce((v_van_visit_retry->>'replayed')::boolean,false) is not true then
    raise exception 'FAIL: van delivery visit retry was not idempotent';
  end if;
  if (select count(*) from public.delivery_shop_visits
      where tenant_id=v_tenant_a and delivery_id=v_van_delivery)<>1 then
    raise exception 'FAIL: van visit retry created duplicate visit records';
  end if;
  if (select coalesce(sum(quantity_in-quantity_out),0) from public.van_stock_movements
      where tenant_id=v_tenant_a and vehicle_number='TX-VAN-01' and product_id=v_product)<>1 then
    raise exception 'FAIL: van sale and market return did not reconcile vehicle stock';
  end if;

  -- Failed visit: zero picked/delivered units must release reservations without issuing stock.
  perform set_config('request.jwt.claim.sub',v_booker_user::text,true);
  v_failed_order:=public.create_order_booker_order(
    v_tenant_a,v_van_route,v_customer,v_failed_order_request,current_date+1,'Smoke test failed van delivery',
    jsonb_build_array(jsonb_build_object('product_id',v_product,'unit_id',v_unit,'quantity',1))
  );
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  update public.sales_orders set status='approved',approved_by=v_user
  where id=v_failed_order and tenant_id=v_tenant_a;
  v_failed_delivery:=(public.create_delivery_for_approved_order(v_failed_order,v_employee)->>'delivery_id')::uuid;
  select id into v_failed_line from public.delivery_lines
  where tenant_id=v_tenant_a and delivery_id=v_failed_delivery;
  perform public.dispatch_van_delivery(
    v_failed_delivery,'TX-VAN-01',
    jsonb_build_array(jsonb_build_object('line_id',v_failed_line,'picked_quantity_base',0))
  );
  v_failed_visit_result:=public.record_van_delivery_visit(
    v_failed_delivery,'not_available',
    jsonb_build_array(jsonb_build_object(
      'delivery_line_id',v_failed_line,'delivered_quantity_base',0,
      'market_return_quantity_base',0,'return_batch_number',null,'return_expiry_date',null
    )),
    'Customer unavailable',
    'TX-VAN-FAILED-0001'
  );
  if coalesce((v_failed_visit_result->>'success')::boolean,false) is not true
     or v_failed_visit_result->>'status'<>'failed'
     or (select status from public.deliveries where id=v_failed_delivery)<>'failed' then
    raise exception 'FAIL: failed van delivery did not close safely: %',v_failed_visit_result;
  end if;

  -- Payroll accrual -> GL -> salary payment -> idempotent payment retry.
  insert into public.payroll_runs(id,tenant_id,run_number,period_start,period_end,pay_date,status,created_by)
  values(v_payroll_run,v_tenant_a,'TX-PAY-001',current_date-30,current_date-1,current_date,'draft',v_user);
  insert into public.payroll_lines(id,tenant_id,payroll_run_id,employee_id,basic_salary,allowances,overtime,deductions,net_salary,sales_incentive)
  values(v_payroll_line,v_tenant_a,v_payroll_run,v_employee,1000,100,0,50,1100,50);
  v_payroll_result:=public.post_payroll_run(v_payroll_run);
  if not exists(select 1 from public.payroll_runs where id=v_payroll_run and status='posted'
    and gross_total=1150 and deductions_total=50 and net_total=1100) then
    raise exception 'FAIL: payroll run did not post expected totals';
  end if;
  v_payment_result:=public.pay_payroll_line(v_payroll_line,'cash','TX-PAY-REF');
  v_payment_retry:=public.pay_payroll_line(v_payroll_line,'cash','TX-PAY-REF');
  if coalesce((v_payment_retry->>'already_paid')::boolean,false) is not true then
    raise exception 'FAIL: paid payroll retry was not idempotent';
  end if;
  if (select count(*) from public.journal_entries where tenant_id=v_tenant_a
    and source_type='payroll_payment' and source_id=v_payroll_line and status='posted')<>1 then
    raise exception 'FAIL: payroll retry created duplicate payment journals';
  end if;

  -- Invalid payroll arithmetic must be rejected without posting the run.
  insert into public.payroll_runs(id,tenant_id,run_number,period_start,period_end,pay_date,status,created_by)
  values(v_bad_payroll_run,v_tenant_a,'TX-PAY-BAD',current_date-30,current_date-1,current_date,'draft',v_user);
  insert into public.payroll_lines(id,tenant_id,payroll_run_id,employee_id,basic_salary,allowances,overtime,deductions,net_salary)
  values(v_bad_payroll_line,v_tenant_a,v_bad_payroll_run,v_employee,1000,0,0,100,1);
  v_rejected:=false;
  begin
    perform public.post_payroll_run(v_bad_payroll_run);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected or (select status from public.payroll_runs where id=v_bad_payroll_run)<>'draft' then
    raise exception 'FAIL: invalid payroll arithmetic was not safely rejected';
  end if;

  -- Fixed asset: monthly depreciation, idempotent retry, and disposal journal.
  insert into public.fixed_asset_account_mappings(
    tenant_id,asset_cost_account_id,accumulated_depreciation_account_id,
    depreciation_expense_account_id,cash_account_id,disposal_gain_account_id,
    disposal_loss_account_id,updated_by
  ) values(
    v_tenant_a,v_asset_cost_account,v_accumulated_account,
    v_depreciation_expense_account,v_account_debit,v_disposal_gain_account,
    v_disposal_loss_account,v_user
  );
  insert into public.fixed_assets(id,tenant_id,asset_code,asset_name,acquisition_date,
    acquisition_cost,salvage_value,useful_life_months,depreciation_method,status,created_by,branch_id)
  values(v_asset,v_tenant_a,'TX-ASSET-001','Smoke Test Delivery Vehicle',
    date_trunc('month',current_date)::date,1200,0,12,'straight_line','active',v_user,v_branch_a);
  v_depreciation_result:=public.post_asset_monthly_depreciation(
    v_asset,date_trunc('month',current_date)::date,current_date,
    v_depreciation_expense_account,v_accumulated_account
  );
  v_depreciation_retry:=public.post_asset_monthly_depreciation(
    v_asset,date_trunc('month',current_date)::date,current_date,
    v_depreciation_expense_account,v_accumulated_account
  );
  if coalesce((v_depreciation_retry->>'already_posted')::boolean,false) is not true then
    raise exception 'FAIL: depreciation retry was not idempotent';
  end if;
  v_disposal_result:=public.dispose_fixed_asset(
    v_asset,current_date,1000,v_asset_cost_account,v_accumulated_account,
    v_account_debit,v_disposal_gain_account,v_disposal_loss_account
  );
  if not exists(select 1 from public.fixed_assets where id=v_asset and status='disposed') then
    raise exception 'FAIL: fixed asset disposal did not update asset status';
  end if;
  if not exists(select 1 from public.journal_entries where tenant_id=v_tenant_a
    and source_type='asset_disposal' and source_id=v_asset and status='posted') then
    raise exception 'FAIL: fixed asset disposal did not post its GL journal';
  end if;

  -- Budget actuals must identify company-wide values and refuse misleading branch attribution.
  insert into public.budgets(id,tenant_id,budget_name,period_start,period_end,status,created_by)
  values(v_budget,v_tenant_a,'Smoke Test Monthly Budget',
    date_trunc('month',current_date)::date,current_date,'draft',v_user);
  insert into public.budget_lines(tenant_id,budget_id,account_id,branch_id,budget_amount,notes)
  values(v_tenant_a,v_budget,v_account_credit,null,1000,'Company-wide sales budget'),
        (v_tenant_a,v_budget,v_account_credit,v_branch_a,500,'Branch sales budget');
  select bool_or(actual_scope_supported) filter(where branch_id is null),
         bool_or(actual_scope_supported) filter(where branch_id=v_branch_a)
    into v_budget_company_supported,v_budget_branch_supported
  from public.get_budget_actuals(v_tenant_a)
  where budget_id=v_budget;
  if v_budget_company_supported is distinct from true then
    raise exception 'FAIL: company-wide budget actuals were not supported';
  end if;
  if v_budget_branch_supported is distinct from true then
    raise exception 'FAIL: branch budget did not recognize source-inferred branch attribution';
  end if;

  -- Export/restore round-trip: same-tenant additive restore must be complete and idempotent.
  v_backup:=public.export_tenant_backup(v_tenant_a);
  if v_backup->>'format'<>'EBS-PRO-TENANT-BACKUP-V1'
     or v_backup->>'tenant_id'<>v_tenant_a::text
     or jsonb_typeof(v_backup->'tables')<>'object' then
    raise exception 'FAIL: tenant backup export format or ownership is invalid';
  end if;
  v_restore:=public.restore_tenant_backup(v_tenant_a,v_backup);
  if coalesce((v_restore->>'success')::boolean,false) is not true
     or coalesce((v_restore->>'complete')::boolean,false) is not true
     or coalesce((v_restore->>'imported_rows')::integer,-1)<>0
     or v_restore->>'mode'<>'additive_only_no_overwrite_no_delete' then
    raise exception 'FAIL: same-tenant backup restore was not complete and idempotent: %',v_restore;
  end if;


  -- Stock transfer: move one available unit between warehouses atomically.
  insert into public.warehouses(id,tenant_id,branch_id,name,code)
  values(v_second_warehouse,v_tenant_a,v_branch_a,'Smoke Test Transfer Warehouse','TX-WH-2');
  insert into public.stock_transfers(
    id,tenant_id,transfer_number,from_warehouse_id,to_warehouse_id,
    transfer_date,status,created_by
  ) values(
    v_stock_transfer,v_tenant_a,'TX-ST-001',v_warehouse,v_second_warehouse,
    current_date,'draft',v_user
  );
  insert into public.stock_transfer_lines(
    id,tenant_id,stock_transfer_id,product_id,quantity_base,unit_cost
  ) values(v_stock_transfer_line,v_tenant_a,v_stock_transfer,v_product,1,0);
  v_stock_transfer_result:=public.post_stock_transfer(v_stock_transfer);
  if coalesce((v_stock_transfer_result->>'success')::boolean,false) is not true
     or v_stock_transfer_result->>'status'<>'posted' then
    raise exception 'FAIL: stock transfer did not post: %',v_stock_transfer_result;
  end if;
  if (select coalesce(sum(quantity_in-quantity_out),0) from public.stock_movements
      where tenant_id=v_tenant_a and warehouse_id=v_warehouse and product_id=v_product)<>1
     or (select coalesce(sum(quantity_in-quantity_out),0) from public.stock_movements
      where tenant_id=v_tenant_a and warehouse_id=v_second_warehouse and product_id=v_product)<>1 then
    raise exception 'FAIL: stock transfer did not preserve source/destination balances';
  end if;

  -- Physical stock count: verify snapshot concurrency guard and variance posting.
  v_stock_take:=public.create_stock_take(
    v_tenant_a,v_warehouse,current_date,
    jsonb_build_array(jsonb_build_object(
      'product_id',v_product,'counted_quantity',0,'expected_quantity',1
    )),
    'Rollback-only stock take acceptance test'
  );
  v_stock_take_result:=public.post_stock_take(v_stock_take);
  if coalesce((v_stock_take_result->>'success')::boolean,false) is not true
     or coalesce((v_stock_take_result->>'adjusted_lines')::integer,-1)<>1 then
    raise exception 'FAIL: physical stock variance did not post: %',v_stock_take_result;
  end if;
  if not exists(select 1 from public.stock_movements
    where tenant_id=v_tenant_a and reference_type='stock_take'
      and reference_id=v_stock_take and quantity_out=1) then
    raise exception 'FAIL: physical stock count did not create the variance movement';
  end if;
  v_rejected:=false;
  begin
    perform public.post_stock_take(v_stock_take);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'FAIL: posted stock take was posted twice'; end if;

  -- Delivery POD: attach a customer signature only after the outcome is saved.
  insert into public.delivery_shop_visits(
    tenant_id,delivery_id,delivery_man_employee_id,customer_id,
    visit_status,shops_visited,line_quantities,created_by
  )
  select v_tenant_a,v_delivery_id,v_employee,v_customer,'delivered',1,'[]'::jsonb,v_user
  on conflict(tenant_id,delivery_id) do update
    set visit_status='delivered',line_quantities='[]'::jsonb;
  v_signature_result:=public.save_delivery_pod_signature(
    v_delivery_id,
    jsonb_build_array(
      jsonb_build_object('x',0.1,'y',0.2),
      jsonb_build_object('x',0.3,'y',0.4)
    )
  );
  if coalesce((v_signature_result->>'success')::boolean,false) is not true
     or (select proof_of_delivery_signature from public.delivery_shop_visits
         where tenant_id=v_tenant_a and delivery_id=v_delivery_id) is null then
    raise exception 'FAIL: delivery POD signature was not persisted';
  end if;

  -- HR: attendance upsert and manager-approved leave decision.
  v_attendance_result:=public.record_employee_attendance(
    v_tenant_a,v_employee,current_date,'present',
    (current_date::text||' 09:00:00+05')::timestamptz,
    (current_date::text||' 17:00:00+05')::timestamptz,
    'Rollback-only attendance acceptance test'
  );
  if coalesce((v_attendance_result->>'success')::boolean,false) is not true
     or not exists(select 1 from public.employee_attendance
       where tenant_id=v_tenant_a and employee_id=v_employee
         and attendance_date=current_date and status='present') then
    raise exception 'FAIL: employee attendance was not recorded';
  end if;
  insert into public.employee_leaves(
    id,tenant_id,employee_id,leave_type,start_date,end_date,total_days,reason,created_by
  ) values(
    v_leave_id,v_tenant_a,v_employee,'annual',current_date+1,current_date+2,2,
    'Rollback-only leave acceptance test',v_user
  );
  v_leave_result:=public.decide_employee_leave(v_leave_id,'approved');
  if coalesce((v_leave_result->>'success')::boolean,false) is not true
     or (select status from public.employee_leaves where id=v_leave_id)<>'approved' then
    raise exception 'FAIL: employee leave approval was not recorded';
  end if;


  -- Custom per-user permission must restrict direct table writes, not just RPC/UI actions.
  update public.tenant_memberships
  set role='manager'
  where tenant_id=v_tenant_a and user_id=v_booker_user;
  insert into public.tenant_user_module_permissions(
    tenant_id,user_id,module_key,can_view,can_create,can_update,can_delete
  ) values(v_tenant_a,v_booker_user,'administration_security',true,true,false,false);
  insert into public.tenant_user_module_permissions(
    tenant_id,user_id,module_key,can_view,can_create,can_update,can_delete
  ) values(v_tenant_a,v_booker_user,'reports_analytics',false,false,false,false);
  insert into public.tenant_user_module_permissions(
    tenant_id,user_id,module_key,can_view,can_create,can_update,can_delete
  ) values
    (v_tenant_a,v_booker_user,'sales_customer',true,false,false,false),
    (v_tenant_a,v_booker_user,'order_booking',true,false,false,false),
    (v_tenant_a,v_booker_user,'inventory',true,false,false,false),
    (v_tenant_a,v_booker_user,'purchase_supplier',true,false,false,false),
    (v_tenant_a,v_booker_user,'accounts_finance',true,false,false,false),
    (v_tenant_a,v_booker_user,'distribution_delivery',true,false,false,false);

  insert into public.app_settings(tenant_id,settings)
  values(v_tenant_a,'{"permission_test":"original"}'::jsonb);
  perform set_config('request.jwt.claim.sub',v_booker_user::text,true);
  execute 'set local role authenticated';

  foreach v_module_key in array array[
    'sales_customer','order_booking','inventory','purchase_supplier',
    'accounts_finance','distribution_delivery','administration_security'
  ] loop
    if not private.module_permission_guard_internal(v_tenant_a,v_module_key,'view') then
      raise exception 'FAIL: custom view grant was not honored for module %',v_module_key;
    end if;
    foreach v_action in array array['create','update','delete'] loop
      if private.module_permission_guard_internal(v_tenant_a,v_module_key,v_action) then
        raise exception 'FAIL: denied % action was granted for module %',v_action,v_module_key;
      end if;
    end loop;
  end loop;
  if private.module_permission_guard_internal(v_tenant_a,'reports_analytics','view') then
    raise exception 'FAIL: explicit reports view denial was ignored';
  end if;
  update public.app_settings
  set settings='{"permission_test":"should_not_change"}'::jsonb
  where tenant_id=v_tenant_a;
  get diagnostics v_rls_rows = row_count;
  execute 'reset role';
  if v_rls_rows<>0 then
    raise exception 'FAIL: direct RLS update bypassed custom per-user update denial';
  end if;
  v_rejected:=false;
  begin
    perform public.get_erp_report_summary(v_tenant_a,current_date,current_date);
  exception when insufficient_privilege then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'FAIL: custom reports view denial was not enforced'; end if;
  if (select settings->>'permission_test' from public.app_settings where tenant_id=v_tenant_a)<>'original' then
    raise exception 'FAIL: denied custom-permission update changed app settings';
  end if;
  perform set_config('request.jwt.claim.sub',v_user::text,true);


  -- Additive restore into a same-tenant fixture with a deliberately missing row.
  insert into public.tenant_memberships(tenant_id,user_id,role,is_active)
  values(v_tenant_b,v_user,'owner',true);
  v_restore_fixture_backup:=public.export_tenant_backup(v_tenant_b);
  if jsonb_typeof(v_restore_fixture_backup->'tables'->'branches')<>'array'
     or jsonb_array_length(v_restore_fixture_backup->'tables'->'branches')<1 then
    raise exception 'FAIL: isolated tenant backup did not include its branch fixture';
  end if;
  delete from public.warehouses where tenant_id=v_tenant_b and branch_id=v_branch_b;
  delete from public.branches where tenant_id=v_tenant_b and id=v_branch_b;
  v_restore_fixture_result:=public.restore_tenant_backup(v_tenant_b,v_restore_fixture_backup);
  if coalesce((v_restore_fixture_result->>'success')::boolean,false) is not true
     or coalesce((v_restore_fixture_result->>'imported_rows')::integer,0)<1
     or not exists(select 1 from public.branches where tenant_id=v_tenant_b and id=v_branch_b) then
    raise exception 'FAIL: additive restore did not recover a missing branch row: %',v_restore_fixture_result;
  end if;


  -- Date-filtered report RPC: totals, breakdowns and custom permissions are reconciled.
  v_report_result:=public.get_erp_report_summary(v_tenant_a,current_date,current_date);
  if jsonb_typeof(v_report_result->'counts')<>'object'
     or jsonb_typeof(v_report_result->'totals')<>'object'
     or jsonb_typeof(v_report_result->'breakdowns')<>'object'
     or coalesce((v_report_result->'counts'->>'sales_orders')::integer,0)<1
     or coalesce((v_report_result->'totals'->>'Posted sales invoices')::numeric,0)<>175.5
     or coalesce((v_report_result->'totals'->>'Accounts receivable')::numeric,0)<>175.5
     or coalesce((v_report_result->'totals'->>'Accounts payable')::numeric,0)<>130
     or coalesce((v_report_result->'totals'->>'Cost of goods issued')::numeric,0)<>60
     or coalesce((v_report_result->'totals'->>'Gross profit (before expenses)')::numeric,0)<>90
     or jsonb_array_length(v_report_result->'breakdowns'->'customers')<1
     or jsonb_array_length(v_report_result->'breakdowns'->'vendors')<1 then
    raise exception 'FAIL: date-filtered report totals or breakdowns did not reconcile: %',v_report_result;
  end if;
  v_rejected:=false;
  begin
    perform public.get_erp_report_summary(v_tenant_a,current_date,current_date-1);
  exception when sqlstate '22007' then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'FAIL: invalid report date range was accepted'; end if;

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
