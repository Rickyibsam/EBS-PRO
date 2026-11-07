-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists sales_invoices_insert on public.sales_invoices;
create policy sales_invoices_insert on public.sales_invoices for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));
drop policy if exists sales_invoices_select on public.sales_invoices;
create policy sales_invoices_select on public.sales_invoices for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales','cashier','warehouse']));
drop policy if exists sales_invoices_initial_totals_update on public.sales_invoices;
create policy sales_invoices_initial_totals_update on public.sales_invoices for update to authenticated
using(status='posted' and grand_total=0 and public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']))
with check(status='posted' and grand_total>0 and public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));
drop policy if exists sales_invoice_lines_insert on public.sales_invoice_lines;
create policy sales_invoice_lines_insert on public.sales_invoice_lines for insert to authenticated with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','warehouse']));
drop policy if exists sales_invoice_lines_select on public.sales_invoice_lines;
create policy sales_invoice_lines_select on public.sales_invoice_lines for select to authenticated using(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales','cashier','warehouse']));
create or replace function public.guard_sales_invoice_initial_totals()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if old.status='posted' and old.grand_total=0 and new.status='posted' and new.grand_total>0
   and (to_jsonb(new)-array['subtotal','tax_total','discount_total','grand_total'])=(to_jsonb(old)-array['subtotal','tax_total','discount_total','grand_total'])
 then return new;end if;
 raise exception 'Posted sales invoices are immutable after initial posting';
end $$;
revoke all on function public.guard_sales_invoice_initial_totals() from public,anon,authenticated;
drop trigger if exists sales_invoice_initial_totals_guard on public.sales_invoices;
create trigger sales_invoice_initial_totals_guard before update on public.sales_invoices for each row execute function public.guard_sales_invoice_initial_totals();
