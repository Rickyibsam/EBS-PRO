-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists purchase_invoices_update on public.purchase_invoices;
create policy purchase_invoices_update on public.purchase_invoices for update to authenticated
using(status='draft' and public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','purchase']))
with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','purchase']));
drop policy if exists purchase_debit_notes_update on public.purchase_debit_notes;
create policy purchase_debit_notes_update on public.purchase_debit_notes for update to authenticated
using(status='draft' and public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','purchase','warehouse']))
with check(public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','purchase','warehouse']));

create or replace function public.guard_purchase_invoice_posting()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if old.status='draft' and new.status='posted'
   and (to_jsonb(new)-array['status','posted_by','posted_at'])=(to_jsonb(old)-array['status','posted_by','posted_at'])
 then return new;end if;
 raise exception 'Supplier invoice is immutable except for its controlled posting transition';
end $$;
revoke all on function public.guard_purchase_invoice_posting() from public,anon,authenticated;
drop trigger if exists purchase_invoice_posting_guard on public.purchase_invoices;
create trigger purchase_invoice_posting_guard before update on public.purchase_invoices for each row execute function public.guard_purchase_invoice_posting();

create or replace function public.guard_purchase_debit_note_posting()
returns trigger language plpgsql set search_path=pg_catalog,public as $$
begin
 if old.status='draft' and new.status='posted'
   and (to_jsonb(new)-array['status','posted_by','posted_at'])=(to_jsonb(old)-array['status','posted_by','posted_at'])
 then return new;end if;
 raise exception 'Posted supplier debit notes are immutable';
end $$;
revoke all on function public.guard_purchase_debit_note_posting() from public,anon,authenticated;
drop trigger if exists purchase_debit_note_posting_guard on public.purchase_debit_notes;
create trigger purchase_debit_note_posting_guard before update on public.purchase_debit_notes for each row execute function public.guard_purchase_debit_note_posting();

create or replace function public.record_party_payment(p_party_id uuid,p_payment_type text,p_amount numeric,p_method text,p_reference_no text,p_notes text,p_payment_date date,p_purchase_invoice_id uuid)
returns jsonb language plpgsql set search_path=pg_catalog,public,auth as $$
declare v_invoice public.purchase_invoices%rowtype;v_paid numeric;v_credits numeric;v_outstanding numeric;v_result jsonb;v_payment uuid;v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Authentication required';end if;
 if p_purchase_invoice_id is null then return public.record_party_payment(p_party_id,p_payment_type,p_amount,p_method,p_reference_no,p_notes,p_payment_date);end if;
 if p_payment_type<>'payment' then raise exception 'Only supplier payments can be allocated to a supplier invoice';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_purchase_invoice_id::text,0));
 select * into v_invoice from public.purchase_invoices where id=p_purchase_invoice_id;
 if not found or v_invoice.supplier_id<>p_party_id then raise exception 'Supplier invoice does not belong to the selected supplier';end if;
 if v_invoice.status<>'posted' then raise exception 'Only posted supplier invoices can receive payments';end if;
 if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Supplier payment permission required';end if;
 select coalesce(sum(amount),0) into v_paid from public.payments where tenant_id=v_invoice.tenant_id and purchase_invoice_id=v_invoice.id and payment_type='payment';
 select coalesce(sum(subtotal),0) into v_credits from public.purchase_debit_notes where tenant_id=v_invoice.tenant_id and goods_receipt_id=v_invoice.goods_receipt_id and status='posted';
 v_outstanding:=greatest(v_invoice.grand_total-v_paid-v_credits,0);
 if p_amount<=0 or p_amount>v_outstanding+0.005 then raise exception 'Payment exceeds the supplier invoice outstanding balance. Outstanding amount: %',v_outstanding;end if;
 v_result:=public.record_party_payment(p_party_id,p_payment_type,p_amount,p_method,p_reference_no,p_notes,p_payment_date);
 v_payment:=(v_result->>'payment_id')::uuid;
 update public.payments set purchase_invoice_id=v_invoice.id where id=v_payment and tenant_id=v_invoice.tenant_id;
 return v_result||jsonb_build_object('purchase_invoice_id',v_invoice.id,'allocated_amount',p_amount,'outstanding',greatest(0,v_outstanding-p_amount));
end $$;
revoke all on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) from public,anon;
grant execute on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) to authenticated;
