-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.payments add column if not exists sales_invoice_id uuid;
do $$
begin
 if not exists(select 1 from pg_constraint where conname='payments_sales_invoice_tenant_fkey' and conrelid='public.payments'::regclass) then
  alter table public.payments add constraint payments_sales_invoice_tenant_fkey
   foreign key(sales_invoice_id,tenant_id) references public.sales_invoices(id,tenant_id);
 end if;
end $$;
create index if not exists payments_tenant_invoice_idx on public.payments(tenant_id,sales_invoice_id) where sales_invoice_id is not null;

create or replace function public.record_invoice_receipt(
 p_invoice_id uuid,p_amount numeric,p_method text,p_reference_no text default null,p_notes text default null
)
returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_user uuid:=auth.uid();
 v_invoice public.sales_invoices%rowtype;
 v_received numeric;
 v_cash_account uuid;
 v_ar_account uuid;
 v_payment_id uuid;
 v_payment_no text;
 v_journal_id uuid;
 v_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_invoice from public.sales_invoices where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.has_tenant_role(v_invoice.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can allocate invoice receipts';
 end if;
 if v_invoice.status<>'posted' then raise exception 'Only posted invoices can receive payment'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Receipt amount must be greater than zero'; end if;
 if p_method not in ('cash','bank','cheque','online','other') then raise exception 'Invalid payment method'; end if;
 select coalesce(sum(amount),0) into v_received from public.payments
  where tenant_id=v_invoice.tenant_id and sales_invoice_id=v_invoice.id and payment_type='receipt';
 if v_received+p_amount>v_invoice.grand_total+0.005 then
  raise exception 'Receipt exceeds invoice balance. Outstanding amount: %',greatest(v_invoice.grand_total-v_received,0);
 end if;
 select id into v_cash_account from public.chart_of_accounts
  where tenant_id=v_invoice.tenant_id and account_code=case when p_method in ('bank','cheque','online') then '1010' else '1000' end and is_active;
 select id into v_ar_account from public.chart_of_accounts
  where tenant_id=v_invoice.tenant_id and account_code='1100' and is_active;
 if v_cash_account is null or v_ar_account is null then raise exception 'Cash/Bank and Accounts Receivable accounts are required'; end if;
 v_payment_no:='EBS-RCPT-'||right(replace(gen_random_uuid()::text,'-',''),10);
 insert into public.payments(tenant_id,party_id,payment_number,payment_type,payment_date,method,amount,reference_no,notes,created_by,sales_invoice_id)
 values(v_invoice.tenant_id,v_invoice.customer_id,v_payment_no,'receipt',current_date,p_method,p_amount,nullif(trim(p_reference_no),''),nullif(trim(p_notes),''),v_user,v_invoice.id)
 returning id into v_payment_id;
 v_journal_no:='EBS-RCPT-JV-'||right(replace(v_payment_id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_invoice.tenant_id,v_journal_no,current_date,'payment',v_payment_id,'Receipt against invoice '||v_invoice.invoice_number,'posted',v_user,v_user,now())
 returning id into v_journal_id;
 insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
 values(v_invoice.tenant_id,v_journal_id,v_cash_account,p_amount,0,'Customer cash/bank receipt'),
       (v_invoice.tenant_id,v_journal_id,v_ar_account,0,p_amount,'Accounts receivable settled');
 return jsonb_build_object('success',true,'payment_id',v_payment_id,'payment_number',v_payment_no,'outstanding',v_invoice.grand_total-v_received-p_amount);
end;
$$;
revoke all on function public.record_invoice_receipt(uuid,numeric,text,text,text) from public,anon;
grant execute on function public.record_invoice_receipt(uuid,numeric,text,text,text) to authenticated;
