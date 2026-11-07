-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

-- Harden exposed functions and keep RLS policies efficient.
alter function public.set_updated_at() set search_path = public;
revoke all on function public.bootstrap_tenant_warehouse() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.create_tenant(text,text,text,text) from public, anon;
grant execute on function public.create_tenant(text,text,text,text) to authenticated;
revoke all on function public.is_tenant_member(uuid) from public, anon;
revoke all on function public.has_tenant_role(uuid,text[]) from public, anon;
grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_role(uuid,text[]) to authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'branches','warehouses','product_categories','units_of_measure','products','product_units',
    'parties','employees','sales_routes','route_assignments','route_customers','booker_visits',
    'purchase_orders','purchase_order_lines','goods_receipts','goods_receipt_lines',
    'sales_orders','sales_order_lines','deliveries','delivery_lines','stock_movements',
    'price_lists','product_prices','customer_price_lists','payments','chart_of_accounts',
    'journal_entries','journal_lines','expenses','document_sequences','app_settings','audit_logs'
  ] loop
    execute format('drop policy if exists tenant_operator_write on public.%I',t);
    execute format('create policy tenant_operator_insert on public.%I for insert to authenticated with check (public.has_tenant_role(tenant_id,array[''owner'',''admin'',''manager'',''accounts'',''purchase'',''sales'',''order_booker'',''warehouse'',''cashier'']))',t);
    execute format('create policy tenant_operator_update on public.%I for update to authenticated using (public.has_tenant_role(tenant_id,array[''owner'',''admin'',''manager'',''accounts'',''purchase'',''sales'',''order_booker'',''warehouse'',''cashier''])) with check (public.has_tenant_role(tenant_id,array[''owner'',''admin'',''manager'',''accounts'',''purchase'',''sales'',''order_booker'',''warehouse'',''cashier'']))',t);
    execute format('create policy tenant_operator_delete on public.%I for delete to authenticated using (public.has_tenant_role(tenant_id,array[''owner'',''admin'']))',t);
    execute format('create index if not exists %I on public.%I(tenant_id)',t||'_tenant_idx',t);
  end loop;
end $$;

drop policy if exists owners_manage_memberships on public.tenant_memberships;
create policy owners_insert_memberships on public.tenant_memberships for insert to authenticated
with check (public.has_tenant_role(tenant_id,array['owner','admin']));
create policy owners_update_memberships on public.tenant_memberships for update to authenticated
using (public.has_tenant_role(tenant_id,array['owner','admin']))
with check (public.has_tenant_role(tenant_id,array['owner','admin']));
create policy owners_delete_memberships on public.tenant_memberships for delete to authenticated
using (public.has_tenant_role(tenant_id,array['owner','admin']));

create index if not exists branches_tenant_code_idx on public.branches(tenant_id,code);
create index if not exists warehouses_tenant_branch_idx on public.warehouses(tenant_id,branch_id);
create index if not exists products_tenant_name_idx on public.products(tenant_id,name);
create index if not exists parties_tenant_name_idx on public.parties(tenant_id,name);
create index if not exists sales_orders_tenant_date_idx on public.sales_orders(tenant_id,order_date desc);
create index if not exists sales_orders_tenant_status_idx on public.sales_orders(tenant_id,status);
create index if not exists purchase_orders_tenant_date_idx on public.purchase_orders(tenant_id,order_date desc);
create index if not exists stock_movements_lookup_idx on public.stock_movements(tenant_id,warehouse_id,product_id,movement_at desc);
create index if not exists booker_visits_customer_date_idx on public.booker_visits(tenant_id,customer_id,visit_at desc);
create index if not exists audit_logs_tenant_created_idx2 on public.audit_logs(tenant_id,created_at desc);
