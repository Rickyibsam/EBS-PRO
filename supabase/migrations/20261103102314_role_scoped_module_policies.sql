-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

-- Role-scoped policies: users only see modules required by their job.
do $$
declare r record;
begin
  for r in
    select * from (values
      ('branches',array['owner','admin','manager','accounts','purchase','sales','order_booker','warehouse','cashier','viewer']::text[],array['owner','admin','manager']::text[]),
      ('warehouses',array['owner','admin','manager','purchase','sales','order_booker','warehouse','cashier','viewer']::text[],array['owner','admin','manager','warehouse']::text[]),
      ('product_categories',array['owner','admin','manager','purchase','sales','order_booker','warehouse','cashier','viewer']::text[],array['owner','admin','manager','purchase']::text[]),
      ('units_of_measure',array['owner','admin','manager','purchase','sales','order_booker','warehouse','cashier','viewer']::text[],array['owner','admin','manager','purchase']::text[]),
      ('products',array['owner','admin','manager','purchase','sales','order_booker','warehouse','cashier','viewer']::text[],array['owner','admin','manager','purchase']::text[]),
      ('product_units',array['owner','admin','manager','purchase','sales','order_booker','warehouse','cashier','viewer']::text[],array['owner','admin','manager','purchase']::text[]),
      ('parties',array['owner','admin','manager','accounts','purchase','sales','order_booker','cashier','viewer']::text[],array['owner','admin','manager','accounts','purchase','sales']::text[]),
      ('employees',array['owner','admin','manager','sales']::text[],array['owner','admin','manager']::text[]),
      ('sales_routes',array['owner','admin','manager','sales','order_booker']::text[],array['owner','admin','manager','sales']::text[]),
      ('route_assignments',array['owner','admin','manager','sales','order_booker']::text[],array['owner','admin','manager','sales']::text[]),
      ('route_customers',array['owner','admin','manager','sales','order_booker']::text[],array['owner','admin','manager','sales']::text[]),
      ('booker_visits',array['owner','admin','manager','sales','order_booker']::text[],array['owner','admin','manager','sales','order_booker']::text[]),
      ('purchase_orders',array['owner','admin','manager','purchase','accounts']::text[],array['owner','admin','manager','purchase']::text[]),
      ('purchase_order_lines',array['owner','admin','manager','purchase','accounts']::text[],array['owner','admin','manager','purchase']::text[]),
      ('goods_receipts',array['owner','admin','manager','purchase','warehouse','accounts']::text[],array['owner','admin','manager','purchase','warehouse']::text[]),
      ('goods_receipt_lines',array['owner','admin','manager','purchase','warehouse','accounts']::text[],array['owner','admin','manager','purchase','warehouse']::text[]),
      ('sales_orders',array['owner','admin','manager','sales','order_booker','cashier','accounts']::text[],array['owner','admin','manager','sales','order_booker','cashier']::text[]),
      ('sales_order_lines',array['owner','admin','manager','sales','order_booker','cashier','accounts']::text[],array['owner','admin','manager','sales','order_booker','cashier']::text[]),
      ('deliveries',array['owner','admin','manager','warehouse','sales']::text[],array['owner','admin','manager','warehouse']::text[]),
      ('delivery_lines',array['owner','admin','manager','warehouse','sales']::text[],array['owner','admin','manager','warehouse']::text[]),
      ('stock_movements',array['owner','admin','manager','warehouse','purchase','sales','accounts']::text[],array['owner','admin','manager','warehouse']::text[]),
      ('price_lists',array['owner','admin','manager','sales','purchase','order_booker']::text[],array['owner','admin','manager','sales']::text[]),
      ('product_prices',array['owner','admin','manager','sales','purchase','order_booker']::text[],array['owner','admin','manager','sales']::text[]),
      ('customer_price_lists',array['owner','admin','manager','sales','order_booker']::text[],array['owner','admin','manager','sales']::text[]),
      ('payments',array['owner','admin','manager','accounts','cashier','sales','order_booker']::text[],array['owner','admin','manager','accounts','cashier']::text[]),
      ('chart_of_accounts',array['owner','admin','manager','accounts']::text[],array['owner','admin','manager','accounts']::text[]),
      ('journal_entries',array['owner','admin','manager','accounts']::text[],array['owner','admin','manager','accounts']::text[]),
      ('journal_lines',array['owner','admin','manager','accounts']::text[],array['owner','admin','manager','accounts']::text[]),
      ('expenses',array['owner','admin','manager','accounts']::text[],array['owner','admin','manager','accounts']::text[]),
      ('document_sequences',array['owner','admin','manager']::text[],array['owner','admin','manager']::text[]),
      ('app_settings',array['owner','admin','manager']::text[],array['owner','admin','manager']::text[]),
      ('audit_logs',array['owner','admin']::text[],array['owner','admin']::text[])
    ) as x(table_name,read_roles,write_roles)
  loop
    execute format('drop policy if exists tenant_member_select on public.%I',r.table_name);
    execute format('drop policy if exists tenant_operator_insert on public.%I',r.table_name);
    execute format('drop policy if exists tenant_operator_update on public.%I',r.table_name);
    execute format('drop policy if exists tenant_operator_delete on public.%I',r.table_name);
    execute format('create policy module_read on public.%I for select to authenticated using (public.has_tenant_role(tenant_id,%L::text[]))',r.table_name,r.read_roles::text);
    execute format('create policy module_insert on public.%I for insert to authenticated with check (public.has_tenant_role(tenant_id,%L::text[]))',r.table_name,r.write_roles::text);
    execute format('create policy module_update on public.%I for update to authenticated using (public.has_tenant_role(tenant_id,%L::text[])) with check (public.has_tenant_role(tenant_id,%L::text[]))',r.table_name,r.write_roles::text,r.write_roles::text);
    execute format('create policy module_delete on public.%I for delete to authenticated using (public.has_tenant_role(tenant_id,array[''owner'',''admin'']))',r.table_name);
  end loop;
end $$;
