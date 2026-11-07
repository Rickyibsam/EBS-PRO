-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create index if not exists sales_orders_tenant_date_idx on public.sales_orders(tenant_id,order_date desc);
create index if not exists purchase_orders_tenant_date_idx on public.purchase_orders(tenant_id,order_date desc);
create index if not exists stock_movements_tenant_warehouse_product_date_idx on public.stock_movements(tenant_id,warehouse_id,product_id,movement_at desc);
create index if not exists deliveries_tenant_date_idx on public.deliveries(tenant_id,delivery_date desc);
create index if not exists payments_tenant_date_idx on public.payments(tenant_id,payment_date desc);
create index if not exists parties_tenant_status_type_idx on public.parties(tenant_id,status,party_type);
create index if not exists products_tenant_active_name_idx on public.products(tenant_id,is_active,name);
create index if not exists goods_receipts_tenant_date_idx on public.goods_receipts(tenant_id,received_date desc);
create index if not exists purchase_order_lines_tenant_order_idx on public.purchase_order_lines(tenant_id,purchase_order_id);
create index if not exists sales_order_lines_tenant_order_idx on public.sales_order_lines(tenant_id,sales_order_id);
create index if not exists delivery_lines_tenant_delivery_idx on public.delivery_lines(tenant_id,delivery_id);
create index if not exists journal_entries_tenant_date_idx on public.journal_entries(tenant_id,entry_date desc);
create index if not exists journal_lines_tenant_entry_idx on public.journal_lines(tenant_id,journal_entry_id);
