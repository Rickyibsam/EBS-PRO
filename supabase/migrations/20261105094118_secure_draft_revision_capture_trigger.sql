-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.capture_draft_voucher_revision()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,auth
as $$
declare
 v_before jsonb;v_after jsonb;v_tenant uuid;v_id uuid;v_status text;v_parent_id uuid;v_parent_table text;v_fk text;
begin
 v_before:=to_jsonb(old);v_tenant:=(v_before->>'tenant_id')::uuid;v_id:=(v_before->>'id')::uuid;
 if tg_table_name in ('sales_orders','purchase_orders','journal_entries','goods_receipts','purchase_invoices','sales_invoices','sales_credit_notes','purchase_debit_notes') then
  v_status:=v_before->>'status';
 else
  case tg_table_name
   when 'sales_order_lines' then v_parent_table:='sales_orders';v_fk:='sales_order_id';
   when 'purchase_order_lines' then v_parent_table:='purchase_orders';v_fk:='purchase_order_id';
   when 'journal_lines' then v_parent_table:='journal_entries';v_fk:='journal_entry_id';
   when 'goods_receipt_lines' then v_parent_table:='goods_receipts';v_fk:='goods_receipt_id';
   when 'purchase_invoice_lines' then v_parent_table:='purchase_invoices';v_fk:='purchase_invoice_id';
   when 'sales_invoice_lines' then v_parent_table:='sales_invoices';v_fk:='sales_invoice_id';
   when 'sales_credit_note_lines' then v_parent_table:='sales_credit_notes';v_fk:='credit_note_id';
   when 'purchase_debit_note_lines' then v_parent_table:='purchase_debit_notes';v_fk:='debit_note_id';
   else v_parent_table:=null;
  end case;
  if v_parent_table is not null then
   v_parent_id:=nullif(v_before->>v_fk,'')::uuid;
   execute format('select status from public.%I where id=$1 and tenant_id=$2',v_parent_table) into v_status using v_parent_id,v_tenant;
  end if;
 end if;
 if v_status='draft' then
  if tg_op='UPDATE' then v_after:=to_jsonb(new); end if;
  insert into public.voucher_revisions(tenant_id,entity_table,entity_id,action,before_data,after_data,changed_by)
  values(v_tenant,tg_table_name,v_id,case when tg_op='UPDATE' then 'updated' else 'deleted' end,v_before,v_after,auth.uid());
 end if;
 if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.capture_draft_voucher_revision() from public,anon,authenticated;
