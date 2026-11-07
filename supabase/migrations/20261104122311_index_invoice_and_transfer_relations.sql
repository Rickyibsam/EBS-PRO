-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create index if not exists sales_invoices_order_tenant_idx on public.sales_invoices(sales_order_id,tenant_id);
create index if not exists sales_invoices_delivery_tenant_idx on public.sales_invoices(delivery_id,tenant_id);
create index if not exists sales_invoices_customer_tenant_idx on public.sales_invoices(customer_id,tenant_id);
create index if not exists sales_invoice_lines_invoice_tenant_idx on public.sales_invoice_lines(sales_invoice_id,tenant_id);
create index if not exists sales_invoice_lines_order_line_tenant_idx on public.sales_invoice_lines(sales_order_line_id,tenant_id);
create index if not exists sales_invoice_lines_product_tenant_idx on public.sales_invoice_lines(product_id,tenant_id);
create index if not exists sales_invoice_lines_unit_tenant_idx on public.sales_invoice_lines(unit_id,tenant_id);
create index if not exists payments_invoice_tenant_idx on public.payments(sales_invoice_id,tenant_id) where sales_invoice_id is not null;
create index if not exists delivery_lines_sales_line_tenant_idx on public.delivery_lines(sales_order_line_id,tenant_id) where sales_order_line_id is not null;
create index if not exists stock_transfers_source_tenant_idx on public.stock_transfers(from_warehouse_id,tenant_id);
create index if not exists stock_transfers_destination_tenant_idx on public.stock_transfers(to_warehouse_id,tenant_id);
create index if not exists stock_transfer_lines_transfer_tenant_idx on public.stock_transfer_lines(stock_transfer_id,tenant_id);
create index if not exists stock_transfer_lines_product_tenant_idx on public.stock_transfer_lines(product_id,tenant_id);
