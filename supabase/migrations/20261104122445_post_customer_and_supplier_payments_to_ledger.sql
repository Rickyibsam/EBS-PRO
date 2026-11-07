-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.record_party_payment(
 p_party_id uuid,p_payment_type text,p_amount numeric,p_method text,
 p_reference_no text default null,p_notes text default null
)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_user uuid:=auth.uid();
 v_party public.parties%rowtype;
 v_cash_account uuid;
 v_control_account uuid;
 v_payment_id uuid;
 v_payment_no text;
 v_journal_id uuid;
 v_journal_no text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_party from public.parties where id=p_party_id for update;
 if not found then raise exception 'Customer or supplier not found'; end if;
 if not public.has_tenant_role(v_party.tenant_id,array['owner','admin','manager','accounts']) then
  raise exception 'Only owner, admin, manager or accounts can post party payments';
 end if;
 if p_amount is null or p_amount<=0 then raise exception 'Payment amount must be greater than zero'; end if;
 if p_method not in ('cash','bank','cheque','online','other') then raise exception 'Invalid payment method'; end if;
 if p_payment_type='receipt' then
  if v_party.party_type not in ('customer','both') then raise exception 'Select a customer for a receipt'; end if;
  select id into v_control_account from public.chart_of_accounts where tenant_id=v_party.tenant_id and account_code='1100' and is_active;
 else
  if p_payment_type<>'payment' or v_party.party_type not in ('supplier','both') then raise exception 'Select a supplier for a payment'; end if;
  select id into v_control_account from public.chart_of_accounts where tenant_id=v_party.tenant_id and account_code='2000' and is_active;
 end if;
 select id into v_cash_account from public.chart_of_accounts where tenant_id=v_party.tenant_id
  and account_code=case when p_method in ('bank','cheque','online') then '1010' else '1000' end and is_active;
 if v_cash_account is null or v_control_account is null then raise exception 'Required Cash/Bank or party control account is missing'; end if;
 v_payment_no:='EBS-PAY-'||right(replace(gen_random_uuid()::text,'-',''),10);
 insert into public.payments(tenant_id,party_id,payment_number,payment_type,payment_date,method,amount,reference_no,notes,created_by)
 values(v_party.tenant_id,v_party.id,v_payment_no,p_payment_type,current_date,p_method,p_amount,nullif(trim(p_reference_no),''),nullif(trim(p_notes),''),v_user)
 returning id into v_payment_id;
 v_journal_no:='EBS-PAY-JV-'||right(replace(v_payment_id::text,'-',''),10);
 insert into public.journal_entries(tenant_id,journal_number,entry_date,source_type,source_id,narration,status,created_by,posted_by,posted_at)
 values(v_party.tenant_id,v_journal_no,current_date,'payment',v_payment_id,
  case when p_payment_type='receipt' then 'Customer receipt from ' else 'Supplier payment to ' end||v_party.name,
  'posted',v_user,v_user,now()) returning id into v_journal_id;
 if p_payment_type='receipt' then
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_party.tenant_id,v_journal_id,v_cash_account,p_amount,0,'Customer receipt'),
        (v_party.tenant_id,v_journal_id,v_control_account,0,p_amount,'Accounts receivable');
 else
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values(v_party.tenant_id,v_journal_id,v_control_account,p_amount,0,'Accounts payable settlement'),
        (v_party.tenant_id,v_journal_id,v_cash_account,0,p_amount,'Supplier payment');
 end if;
 return jsonb_build_object('success',true,'payment_id',v_payment_id,'payment_number',v_payment_no);
end;
$$;
revoke all on function public.record_party_payment(uuid,text,numeric,text,text,text) from public,anon;
grant execute on function public.record_party_payment(uuid,text,numeric,text,text,text) to authenticated;
