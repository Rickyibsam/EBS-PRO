-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

do $$
declare d text;
begin
 select pg_get_functiondef('public.update_draft_voucher_lines(uuid,text,uuid,jsonb)'::regprocedure) into d;
 d:=replace(d,
 'update public.purchase_debit_note_lines set quantity=x.quantity,unit_cost=x.unit_cost,line_total=x.quantity*x.unit_cost where id=x.id and tenant_id=p_tenant_id and debit_note_id=p_voucher_id;',
 'update public.purchase_debit_note_lines set quantity=x.quantity,quantity_base=x.quantity*coalesce((select gr.conversion_to_base from public.goods_receipt_lines gr where gr.id=public.purchase_debit_note_lines.goods_receipt_line_id and gr.tenant_id=p_tenant_id),1),unit_cost=x.unit_cost,line_total=x.quantity*x.unit_cost where id=x.id and tenant_id=p_tenant_id and debit_note_id=p_voucher_id;');
 execute d;
end;
$$;
