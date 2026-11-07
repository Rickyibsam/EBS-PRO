-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

grant update on public.sales_orders,public.purchase_orders,public.journal_entries,public.goods_receipts,public.purchase_invoices,public.sales_invoices,public.sales_credit_notes,public.purchase_debit_notes,
 public.sales_order_lines,public.purchase_order_lines,public.journal_lines,public.goods_receipt_lines,public.purchase_invoice_lines,public.sales_invoice_lines,public.sales_credit_note_lines,public.purchase_debit_note_lines to authenticated;

do $$
declare t text; line_table text; fk text;
begin
 foreach t in array array['sales_orders','purchase_orders','journal_entries','goods_receipts','purchase_invoices','sales_invoices','sales_credit_notes','purchase_debit_notes'] loop
  execute format('drop policy if exists accounts_draft_voucher_header_update on public.%I',t);
  execute format('create policy accounts_draft_voucher_header_update on public.%I for update to authenticated using (public.has_tenant_role(tenant_id,array[''owner'',''admin'',''manager'',''accounts'']) and status=''draft'') with check (public.has_tenant_role(tenant_id,array[''owner'',''admin'',''manager'',''accounts'']) and status=''draft'')',t);
 end loop;
 foreach t in array array['sales_order_lines','purchase_order_lines','journal_lines','goods_receipt_lines','purchase_invoice_lines','sales_invoice_lines','sales_credit_note_lines','purchase_debit_note_lines'] loop
  case t
   when 'sales_order_lines' then line_table:='sales_orders';fk:='sales_order_id';
   when 'purchase_order_lines' then line_table:='purchase_orders';fk:='purchase_order_id';
   when 'journal_lines' then line_table:='journal_entries';fk:='journal_entry_id';
   when 'goods_receipt_lines' then line_table:='goods_receipts';fk:='goods_receipt_id';
   when 'purchase_invoice_lines' then line_table:='purchase_invoices';fk:='purchase_invoice_id';
   when 'sales_invoice_lines' then line_table:='sales_invoices';fk:='sales_invoice_id';
   when 'sales_credit_note_lines' then line_table:='sales_credit_notes';fk:='credit_note_id';
   when 'purchase_debit_note_lines' then line_table:='purchase_debit_notes';fk:='debit_note_id';
  end case;
  execute format('drop policy if exists accounts_draft_voucher_line_update on public.%I',t);
  execute format('create policy accounts_draft_voucher_line_update on public.%I for update to authenticated using (public.has_tenant_role(tenant_id,array[''owner'',''admin'',''manager'',''accounts'']) and exists(select 1 from public.%I h where h.id=%I and h.tenant_id=%I.tenant_id and h.status=''draft'')) with check (public.has_tenant_role(tenant_id,array[''owner'',''admin'',''manager'',''accounts'']) and exists(select 1 from public.%I h where h.id=%I and h.tenant_id=%I.tenant_id and h.status=''draft''))',t,line_table,fk,t,line_table,fk,t);
 end loop;
end;
$$;
