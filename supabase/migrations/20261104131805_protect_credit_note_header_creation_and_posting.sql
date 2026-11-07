-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

CREATE OR REPLACE FUNCTION private.protect_sales_credit_note_header()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if tg_op='INSERT' then
  if new.status<>'draft' or new.subtotal<>0 or new.tax_total<>0 or new.discount_total<>0 or new.grand_total<>0 then
   raise exception 'New credit notes must begin as zero-value drafts';
  end if;
  if not exists(select 1 from public.sales_invoices i where i.id=new.sales_invoice_id and i.tenant_id=new.tenant_id and i.customer_id=new.customer_id and i.status='posted') then
   raise exception 'Credit note must reference a posted invoice for the same customer and company';
  end if;
  return new;
 end if;
 if tg_op='DELETE' then
  if old.status='posted' then raise exception 'Posted credit notes cannot be deleted'; end if;
  return old;
 end if;
 if old.status='posted' then raise exception 'Posted credit notes cannot be modified'; end if;
 if new.status='posted' and current_setting('ebs.credit_note_posting',true) is distinct from old.id::text then
  raise exception 'Use the controlled credit note posting workflow';
 end if;
 return new;
end;
$function$
;
drop trigger if exists sales_credit_note_header_protection on public.sales_credit_notes;
create trigger sales_credit_note_header_protection before insert or update or delete on public.sales_credit_notes for each row execute function private.protect_sales_credit_note_header();
