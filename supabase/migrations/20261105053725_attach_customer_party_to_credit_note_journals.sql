-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.attach_party_to_control_journal_line()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_code text;v_source text;v_source_id uuid;v_party uuid;
begin
 if new.party_id is not null then return new;end if;
 select account_code into v_code from public.chart_of_accounts where id=new.account_id and tenant_id=new.tenant_id;
 if v_code not in ('1100','2000') then return new;end if;
 select source_type,source_id into v_source,v_source_id from public.journal_entries where id=new.journal_entry_id and tenant_id=new.tenant_id;
 if v_source='sales_invoice' and v_code='1100' then
  select customer_id into v_party from public.sales_invoices where id=v_source_id and tenant_id=new.tenant_id;
 elsif v_source='sales_credit_note' and v_code='1100' then
  select customer_id into v_party from public.sales_credit_notes where id=v_source_id and tenant_id=new.tenant_id;
 elsif v_source='purchase_invoice' and v_code='2000' then
  select supplier_id into v_party from public.purchase_invoices where id=v_source_id and tenant_id=new.tenant_id;
 elsif v_source='purchase_return' and v_code='2000' then
  select supplier_id into v_party from public.purchase_debit_notes where id=v_source_id and tenant_id=new.tenant_id;
 elsif v_source='payment' then
  select party_id into v_party from public.payments where id=v_source_id and tenant_id=new.tenant_id;
 end if;
 if v_party is not null then new.party_id:=v_party;end if;
 return new;
end $$;
revoke all on function public.attach_party_to_control_journal_line() from public,anon,authenticated;
