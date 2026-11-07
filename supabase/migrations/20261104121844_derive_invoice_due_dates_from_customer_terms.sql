-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.set_sales_invoice_due_date()
returns trigger language plpgsql
security invoker
set search_path=pg_catalog,public
as $$
declare v_terms integer;
begin
 if new.due_date is null then
  select coalesce(payment_terms_days,0) into v_terms from public.parties
   where id=new.customer_id and tenant_id=new.tenant_id;
  new.due_date:=coalesce(new.invoice_date,current_date)+coalesce(v_terms,0);
 end if;
 return new;
end;
$$;
drop trigger if exists sales_invoice_due_date_before_insert on public.sales_invoices;
create trigger sales_invoice_due_date_before_insert
before insert on public.sales_invoices
for each row execute function public.set_sales_invoice_due_date();
