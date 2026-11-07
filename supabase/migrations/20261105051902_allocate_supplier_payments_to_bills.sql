-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.payments add column if not exists purchase_invoice_id uuid;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='payments_purchase_invoice_tenant_fk') then
  alter table public.payments add constraint payments_purchase_invoice_tenant_fk foreign key(purchase_invoice_id,tenant_id) references public.purchase_invoices(id,tenant_id);
 end if;
end $$;
create index if not exists payments_purchase_invoice_idx on public.payments(tenant_id,purchase_invoice_id) where purchase_invoice_id is not null;
create or replace function public.record_party_payment(p_party_id uuid,p_payment_type text,p_amount numeric,p_method text,p_reference_no text,p_notes text,p_payment_date date,p_purchase_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_invoice public.purchase_invoices%rowtype;v_paid numeric;v_result jsonb;v_payment uuid;v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Authentication required';end if;
 if p_purchase_invoice_id is null then return public.record_party_payment(p_party_id,p_payment_type,p_amount,p_method,p_reference_no,p_notes,p_payment_date);end if;
 if p_payment_type<>'payment' then raise exception 'Only supplier payments can be allocated to a supplier invoice';end if;
 select * into v_invoice from public.purchase_invoices where id=p_purchase_invoice_id for update;
 if not found or v_invoice.supplier_id<>p_party_id then raise exception 'Supplier invoice does not belong to the selected supplier';end if;
 if v_invoice.status<>'posted' then raise exception 'Only posted supplier invoices can receive payments';end if;
 if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then raise exception 'Supplier payment permission required';end if;
 select coalesce(sum(amount),0) into v_paid from public.payments where tenant_id=v_invoice.tenant_id and purchase_invoice_id=v_invoice.id and payment_type='payment';
 if p_amount<=0 or p_amount>v_invoice.grand_total-v_paid+0.005 then raise exception 'Payment exceeds the supplier invoice outstanding balance';end if;
 v_result:=public.record_party_payment(p_party_id,p_payment_type,p_amount,p_method,p_reference_no,p_notes,p_payment_date);
 v_payment:=(v_result->>'payment_id')::uuid;
 update public.payments set purchase_invoice_id=v_invoice.id where id=v_payment and tenant_id=v_invoice.tenant_id;
 return v_result||jsonb_build_object('purchase_invoice_id',v_invoice.id,'allocated_amount',p_amount,'outstanding',greatest(0,v_invoice.grand_total-v_paid-p_amount));
end $$;
revoke all on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) from public;
grant execute on function public.record_party_payment(uuid,text,numeric,text,text,text,date,uuid) to authenticated;
