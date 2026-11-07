-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.sales_invoice_lines
 add constraint sales_invoice_lines_discount_below_gross
 check(discount_amount>=0 and discount_amount < quantity*unit_price);
