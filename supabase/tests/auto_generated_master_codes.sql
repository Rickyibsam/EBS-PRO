-- Rollback-only integration check for generated master codes.
begin;
do $$
declare
  v_tenant uuid;
  v_product_code text;
  v_customer_code text;
  v_supplier_code text;
  v_custom_code text;
  v_new_branch uuid;
  v_branch_code text;
  v_new_warehouse_code text;
  v_branch uuid;
  v_code text;
begin
  select id into v_tenant from public.organizations order by created_at limit 1;
  if v_tenant is null then
    raise exception 'A test organization is required for master-code acceptance';
  end if;

  insert into public.products(tenant_id, sku, name)
  values (v_tenant, '', 'EBS code-generation test product')
  returning sku into v_product_code;
  if v_product_code !~ '^SKU-[0-9]{6}$' then raise exception 'Product code failed: %',v_product_code; end if;

  insert into public.parties(tenant_id, party_code, party_type, name)
  values (v_tenant, '', 'customer', 'EBS code-generation test customer')
  returning party_code into v_customer_code;
  if v_customer_code !~ '^CUS-[0-9]{6}$' then raise exception 'Customer code failed: %',v_customer_code; end if;

  insert into public.parties(tenant_id, party_code, party_type, name)
  values (v_tenant, '', 'supplier', 'EBS code-generation test supplier')
  returning party_code into v_supplier_code;
  if v_supplier_code !~ '^SUP-[0-9]{6}$' then raise exception 'Supplier code failed: %',v_supplier_code; end if;

  insert into public.parties(tenant_id, party_code, party_type, name)
  values (v_tenant, 'LEGACY-CODE-KEEP', 'customer', 'EBS legacy code preservation test')
  returning party_code into v_custom_code;
  if v_custom_code <> 'LEGACY-CODE-KEEP' then raise exception 'A supplied legacy code was unexpectedly changed'; end if;

  insert into public.branches(tenant_id,name,code)
  values(v_tenant,'EBS code test branch','')
  returning id,code into v_new_branch,v_branch_code;
  if v_branch_code !~ '^BR-[0-9]{6}$' then raise exception 'Branch code failed: %',v_branch_code; end if;

  select code into v_new_warehouse_code from public.warehouses
  where tenant_id=v_tenant and branch_id=v_new_branch;
  if v_new_warehouse_code !~ '^WH-[0-9]{6}$' then raise exception 'Branch bootstrap warehouse code failed: %',v_new_warehouse_code; end if;

  select id into v_branch from public.branches
  where tenant_id=v_tenant and is_active order by created_at limit 1;
  if v_branch is null then raise exception 'An active test branch is required'; end if;

  insert into public.warehouses(tenant_id,branch_id,name,code)
  values(v_tenant,v_branch,'EBS code test warehouse','')
  returning code into v_code;
  if v_code !~ '^WH-[0-9]{6}$' then raise exception 'Warehouse code failed: %',v_code; end if;

  insert into public.departments(tenant_id,name,code)
  values(v_tenant,'EBS code test department','') returning code into v_code;
  if v_code !~ '^DEP-[0-9]{6}$' then raise exception 'Department code failed: %',v_code; end if;

  insert into public.designations(tenant_id,name,code)
  values(v_tenant,'EBS code test designation','') returning code into v_code;
  if v_code !~ '^DSG-[0-9]{6}$' then raise exception 'Designation code failed: %',v_code; end if;

  insert into public.employees(tenant_id,full_name,employee_code)
  values(v_tenant,'EBS code test employee','') returning employee_code into v_code;
  if v_code !~ '^EMP-[0-9]{6}$' then raise exception 'Employee code failed: %',v_code; end if;

  insert into public.fixed_assets(tenant_id,asset_name,asset_code,acquisition_date,acquisition_cost,useful_life_months)
  values(v_tenant,'EBS code test asset','',current_date,1,12) returning asset_code into v_code;
  if v_code !~ '^AST-[0-9]{6}$' then raise exception 'Asset code failed: %',v_code; end if;

  insert into public.sales_routes(tenant_id,name,route_code)
  values(v_tenant,'EBS code test route','') returning route_code into v_code;
  if v_code !~ '^RTE-[0-9]{6}$' then raise exception 'Route code failed: %',v_code; end if;
end $$;
rollback;
