-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.prevent_posted_voucher_mutation()
returns trigger language plpgsql security invoker
set search_path=pg_catalog,public,pg_temp
as $$
declare v_parent_id uuid; v_status text; v_parent_table text; v_fk text; v_record jsonb;
begin
 if tg_table_name in ('sales_orders','purchase_orders','journal_entries','goods_receipts','purchase_invoices','sales_invoices','sales_credit_notes','purchase_debit_notes') then
  if tg_op='DELETE' then
   if lower(coalesce(to_jsonb(old)->>'status','')) in ('posted','approved') then raise exception 'Approved or posted vouchers cannot be deleted.' using errcode='55000'; end if;
   return old;
  end if;
  if tg_op='UPDATE' then
   if lower(coalesce(to_jsonb(old)->>'status',''))='posted' then raise exception 'Posted vouchers are immutable. Use a reversal or adjustment voucher.' using errcode='55000'; end if;
   if lower(coalesce(to_jsonb(old)->>'status',''))='approved'
      and (to_jsonb(new)-array['status','approved_by','updated_at']) is distinct from (to_jsonb(old)-array['status','approved_by','updated_at']) then
    raise exception 'Approved vouchers are locked. Only controlled workflow status changes are allowed.' using errcode='55000';
   end if;
   return new;
  end if;
  return new;
 end if;
 case tg_table_name
  when 'sales_order_lines' then v_parent_table:='sales_orders';v_fk:='sales_order_id';
  when 'purchase_order_lines' then v_parent_table:='purchase_orders';v_fk:='purchase_order_id';
  when 'journal_lines' then v_parent_table:='journal_entries';v_fk:='journal_entry_id';
  when 'goods_receipt_lines' then v_parent_table:='goods_receipts';v_fk:='goods_receipt_id';
  when 'purchase_invoice_lines' then v_parent_table:='purchase_invoices';v_fk:='purchase_invoice_id';
  when 'sales_invoice_lines' then v_parent_table:='sales_invoices';v_fk:='sales_invoice_id';
  when 'sales_credit_note_lines' then v_parent_table:='sales_credit_notes';v_fk:='credit_note_id';
  when 'purchase_debit_note_lines' then v_parent_table:='purchase_debit_notes';v_fk:='debit_note_id';
  else if tg_op='DELETE' then return old; else return new; end if;
 end case;
 if tg_op<>'INSERT' then
  v_record:=to_jsonb(old);v_parent_id:=nullif(v_record->>v_fk,'')::uuid;
  if v_parent_id is not null then
   execute format('select status from public.%I where id=$1',v_parent_table) into v_status using v_parent_id;
   if lower(coalesce(v_status,'')) in ('posted','approved') then raise exception 'Lines belonging to an approved or posted voucher cannot be changed.' using errcode='55000'; end if;
  end if;
 end if;
 if tg_op<>'DELETE' then
  v_record:=to_jsonb(new);v_parent_id:=nullif(v_record->>v_fk,'')::uuid;
  if v_parent_id is not null then
   execute format('select status from public.%I where id=$1',v_parent_table) into v_status using v_parent_id;
   if lower(coalesce(v_status,'')) in ('posted','approved') then raise exception 'Lines cannot be inserted into or moved to an approved or posted voucher.' using errcode='55000'; end if;
  end if;
 end if;
 if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

do $$
declare t text;
begin
 foreach t in array array['sales_orders','purchase_orders','journal_entries','goods_receipts','purchase_invoices','sales_invoices','sales_credit_notes','purchase_debit_notes'] loop
  execute format('drop trigger if exists trg_prevent_posted_voucher_mutation on public.%I',t);
  execute format('create trigger trg_prevent_posted_voucher_mutation before update or delete on public.%I for each row execute function public.prevent_posted_voucher_mutation()',t);
 end loop;
 foreach t in array array['sales_order_lines','purchase_order_lines','journal_lines','goods_receipt_lines','purchase_invoice_lines','sales_invoice_lines','sales_credit_note_lines','purchase_debit_note_lines'] loop
  execute format('drop trigger if exists trg_prevent_posted_voucher_mutation on public.%I',t);
  execute format('create trigger trg_prevent_posted_voucher_mutation before insert or update or delete on public.%I for each row execute function public.prevent_posted_voucher_mutation()',t);
 end loop;
end;
$$;
