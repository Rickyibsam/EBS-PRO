-- Rollback-only integration check for generated master codes.
begin;
do $$
declare
  v_tenant uuid;
  v_product_code text;
  v_customer_code text;
  v_supplier_code text;
  v_custom_code text;
begin
  select id into v_tenant from public.organizations order by created_at limit 1;
  if v_tenant is null then
    raise exception 'A test organization is required for master-code acceptance';
  end if;

  insert into public.products(tenant_id, sku, name)
  values (v_tenant, '', 'EBS code-generation test product')
  returning sku into v_product_code;
  if v_product_code !~ '^SKU-[0-9]{6}$' then
    raise exception 'Product SKU was not generated: %', v_product_code;
  end if;

  insert into public.parties(tenant_id, party_code, party_type, name)
  values (v_tenant, '', 'customer', 'EBS code-generation test customer')
  returning party_code into v_customer_code;
  if v_customer_code !~ '^CUS-[0-9]{6}$' then
    raise exception 'Customer code was not generated: %', v_customer_code;
  end if;

  insert into public.parties(tenant_id, party_code, party_type, name)
  values (v_tenant, '', 'supplier', 'EBS code-generation test supplier')
  returning party_code into v_supplier_code;
  if v_supplier_code !~ '^SUP-[0-9]{6}$' then
    raise exception 'Supplier code was not generated: %', v_supplier_code;
  end if;

  insert into public.parties(tenant_id, party_code, party_type, name)
  values (v_tenant, 'LEGACY-CODE-KEEP', 'customer', 'EBS legacy code preservation test')
  returning party_code into v_custom_code;
  if v_custom_code <> 'LEGACY-CODE-KEEP' then
    raise exception 'A supplied legacy code was unexpectedly changed';
  end if;

  if v_product_code = '' or v_customer_code = '' or v_supplier_code = '' then
    raise exception 'Generated code cannot be blank';
  end if;
end $$;
rollback;
