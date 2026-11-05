-- Restore a deleted or edited line from the immutable draft voucher revision log.
-- All current lines are resubmitted through the same atomic validator used by the editor.

create or replace function public.restore_draft_voucher_line_revision(p_revision_id uuid)
returns jsonb language plpgsql security invoker
set search_path=pg_catalog,public,auth
as $$
declare
 v_user uuid:=auth.uid();v_rev public.voucher_revisions%rowtype;
 v_line_table text;v_parent_table text;v_fk text;v_parent_id uuid;v_status text;
 v_cols text;v_payload jsonb;v_inserted integer;
begin
 if v_user is null then raise exception 'Authentication required.'; end if;
 select * into v_rev from public.voucher_revisions where id=p_revision_id for update;
 if not found then raise exception 'Voucher revision was not found.'; end if;
 if not public.has_tenant_role(v_rev.tenant_id,array['owner','admin','manager','accounts','sales','warehouse']) then raise exception 'You cannot restore voucher revisions.' using errcode='42501'; end if;
 if v_rev.action not in ('updated','deleted') or v_rev.before_data is null then raise exception 'Only updated or deleted line snapshots can be restored.'; end if;
 v_line_table:=v_rev.entity_table;
 case v_line_table
  when 'sales_order_lines' then v_parent_table:='sales_orders';v_fk:='sales_order_id';
  when 'purchase_order_lines' then v_parent_table:='purchase_orders';v_fk:='purchase_order_id';
  when 'journal_lines' then v_parent_table:='journal_entries';v_fk:='journal_entry_id';
  when 'goods_receipt_lines' then v_parent_table:='goods_receipts';v_fk:='goods_receipt_id';
  when 'purchase_invoice_lines' then v_parent_table:='purchase_invoices';v_fk:='purchase_invoice_id';
  when 'sales_invoice_lines' then v_parent_table:='sales_invoices';v_fk:='sales_invoice_id';
  when 'sales_credit_note_lines' then v_parent_table:='sales_credit_notes';v_fk:='credit_note_id';
  when 'purchase_debit_note_lines' then v_parent_table:='purchase_debit_notes';v_fk:='debit_note_id';
  else raise exception 'This line type cannot be restored through the voucher editor.';
 end case;
 if (v_rev.before_data->>'tenant_id')::uuid is distinct from v_rev.tenant_id or (v_rev.before_data->>'id')::uuid is distinct from v_rev.entity_id then raise exception 'Revision snapshot does not match its tenant or line ID.'; end if;
 v_parent_id:=nullif(v_rev.before_data->>v_fk,'')::uuid;
 if v_parent_id is null then raise exception 'Revision snapshot is missing its parent voucher ID.'; end if;
 execute format('select status from public.%I where id=$1 and tenant_id=$2 for update',v_parent_table) into v_status using v_parent_id,v_rev.tenant_id;
 if v_status is distinct from 'draft' then raise exception 'Only a draft parent voucher can receive a restored line.'; end if;
 if v_rev.action='deleted' then
  select string_agg(quote_ident(column_name),',' order by ordinal_position) into v_cols
  from information_schema.columns where table_schema='public' and table_name=v_line_table and is_generated='NEVER' and is_identity='NO';
  execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I,$1) on conflict do nothing',v_line_table,v_cols,v_cols,v_line_table)
   using jsonb_build_array(v_rev.before_data);
  get diagnostics v_inserted=row_count;
  if v_inserted<>1 then raise exception 'Deleted voucher line could not be restored because its ID or unique key already exists.'; end if;
 end if;
 execute format('select coalesce(jsonb_agg(case when id=$1 then $2 else to_jsonb(x) end),''[]''::jsonb) from public.%I x where tenant_id=$3 and %I=$4',v_line_table,v_fk)
  into v_payload using v_rev.entity_id,v_rev.before_data,v_rev.tenant_id,v_parent_id;
 if jsonb_typeof(v_payload)<>'array' or jsonb_array_length(v_payload)=0 then raise exception 'No draft lines remain to restore.'; end if;
 perform public.update_draft_voucher_lines(v_rev.tenant_id,v_parent_table,v_parent_id,v_payload);
 return jsonb_build_object('success',true,'restored_line_id',v_rev.entity_id,'voucher_table',v_parent_table,'voucher_id',v_parent_id,'line_count',jsonb_array_length(v_payload));
end;
$$;
revoke all on function public.restore_draft_voucher_line_revision(uuid) from public,anon;
grant execute on function public.restore_draft_voucher_line_revision(uuid) to authenticated;
