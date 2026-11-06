-- Harden purchase-return source reconciliation and make salary payment retries idempotent.
-- These are function-only changes; no business rows are modified.
do $$
declare
  v_definition text;
  v_old_decl text := 'v_no text;';
  v_new_decl text := 'v_no text;v_receipt_line public.goods_receipt_lines%rowtype;v_prior_returned numeric;v_received_base numeric;';
  v_old_invoice text := $old$if not exists(select 1 from public.purchase_invoices where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and status='posted') then raise exception 'Post the matched supplier invoice before posting its purchase return';end if;$old$;
  v_new_invoice text := $new$if not exists(select 1 from public.purchase_invoices where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and supplier_id=v_note.supplier_id and status='posted') then raise exception 'Post the matched supplier invoice for this supplier and goods receipt before posting its purchase return';end if;
 if not exists(select 1 from public.goods_receipts where tenant_id=v_note.tenant_id and id=v_note.goods_receipt_id and warehouse_id=v_note.warehouse_id) then raise exception 'Purchase return warehouse must match its source goods receipt';end if;$new$;
  v_old_lines text := $old$if not exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id) then raise exception 'Purchase return has no lines';end if;
 for v_line in select * from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id loop
  perform pg_advisory_xact_lock(hashtextextended(v_note.tenant_id::text||':'||v_note.warehouse_id::text||':'||v_line.product_id::text,0));$old$;
  v_new_lines text := $new$if not exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id) then raise exception 'Purchase return has no lines';end if;
 if exists(select 1 from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id and (quantity_base<=0 or line_total<0)) then raise exception 'Purchase return lines must have positive quantities and non-negative values';end if;
 if abs(coalesce((select sum(line_total) from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id),0)-coalesce(v_note.subtotal,0))>0.01 then raise exception 'Purchase return header subtotal must equal the sum of its line totals';end if;
 for v_line in select * from public.purchase_debit_note_lines where tenant_id=v_note.tenant_id and debit_note_id=v_note.id loop
  select * into v_receipt_line from public.goods_receipt_lines where tenant_id=v_note.tenant_id and goods_receipt_id=v_note.goods_receipt_id and id=v_line.goods_receipt_line_id for update;
  if not found then raise exception 'Every purchase return line must reference a line from its source goods receipt';end if;
  if v_receipt_line.product_id is distinct from v_line.product_id or v_receipt_line.batch_number is distinct from v_line.batch_number or v_receipt_line.expiry_date is distinct from v_line.expiry_date then raise exception 'Purchase return product, batch and expiry must match the source goods receipt line';end if;
  v_received_base:=coalesce(v_receipt_line.accepted_quantity,0)*coalesce(v_receipt_line.conversion_to_base,1);
  select coalesce(sum(l.quantity_base),0) into v_prior_returned
  from public.purchase_debit_note_lines l join public.purchase_debit_notes n on n.id=l.debit_note_id and n.tenant_id=l.tenant_id
  where l.tenant_id=v_note.tenant_id and l.goods_receipt_line_id=v_receipt_line.id and n.status='posted';
  if v_prior_returned+v_line.quantity_base>v_received_base+0.000001 then raise exception 'Return quantity exceeds accepted source receipt quantity. Received %, previously returned %, requested %',v_received_base,v_prior_returned,v_line.quantity_base;end if;
  perform pg_advisory_xact_lock(hashtextextended(v_note.tenant_id::text||':'||v_note.warehouse_id::text||':'||v_line.product_id::text,0));$new$;
begin
  select pg_get_functiondef('public.post_purchase_debit_note(uuid)'::regprocedure) into v_definition;
  if position(v_old_decl in v_definition)=0 or position(v_old_invoice in v_definition)=0 or position(v_old_lines in v_definition)=0 then
    raise exception 'Expected purchase-return function blocks were not found; no function was changed.';
  end if;
  v_definition:=replace(v_definition,v_old_decl,v_new_decl);
  v_definition:=replace(v_definition,v_old_invoice,v_new_invoice);
  v_definition:=replace(v_definition,v_old_lines,v_new_lines);
  execute v_definition;
end $$;

do $$
declare
  v_definition text;
  v_old text := $old$if v_line.payment_status='paid' then raise exception 'This salary has already been paid';end if;$old$;
  v_new text := $new$if v_line.payment_status='paid' then
  select id into v_journal from public.journal_entries
   where tenant_id=v_line.tenant_id and source_type='payroll_payment' and source_id=v_line.id and status='posted'
   order by created_at desc limit 1;
  if v_journal is null then raise exception 'Salary is marked paid but its posted payment journal is missing. Run reconciliation before retrying.' using errcode='23514';end if;
  return jsonb_build_object('success',true,'status','paid','already_paid',true,'journal_entry_id',v_journal);
 end if;$new$;
begin
  select pg_get_functiondef('public.pay_payroll_line(uuid,text,text)'::regprocedure) into v_definition;
  if position(v_old in v_definition)=0 then
    raise exception 'Expected payroll payment retry guard was not found; no function was changed.';
  end if;
  v_definition:=replace(v_definition,v_old,v_new);
  execute v_definition;
end $$;
