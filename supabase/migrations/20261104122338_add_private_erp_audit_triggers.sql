-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create or replace function private.audit_erp_changes()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,auth
as $$
declare
 v_row jsonb;
 v_before jsonb;
 v_after jsonb;
 v_tenant uuid;
 v_entity uuid;
begin
 if tg_op='INSERT' then
  v_after:=to_jsonb(new);
  v_row:=v_after;
 elsif tg_op='UPDATE' then
  v_before:=to_jsonb(old);
  v_after:=to_jsonb(new);
  v_row:=v_after;
 else
  v_before:=to_jsonb(old);
  v_row:=v_before;
 end if;
 v_tenant:=(v_row->>'tenant_id')::uuid;
 v_entity:=(v_row->>'id')::uuid;
 if v_tenant is not null then
  insert into public.audit_logs(tenant_id,actor_id,action,entity_type,entity_id,before_data,after_data)
  values(v_tenant,auth.uid(),lower(tg_op),tg_table_name,v_entity,v_before,v_after);
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$$;
revoke all on function private.audit_erp_changes() from public,anon,authenticated;

do $$
declare t text;
begin
 foreach t in array array[
  'sales_orders','sales_order_lines','purchase_orders','purchase_order_lines',
  'goods_receipts','goods_receipt_lines','stock_movements','stock_transfers','stock_transfer_lines',
  'deliveries','delivery_lines','sales_invoices','sales_invoice_lines',
  'payments','expenses','journal_entries','journal_lines'
 ] loop
  execute format('drop trigger if exists audit_erp_changes on public.%I',t);
  execute format('create trigger audit_erp_changes after insert or update or delete on public.%I for each row execute function private.audit_erp_changes()',t);
 end loop;
end $$;

create index if not exists audit_logs_tenant_created_idx on public.audit_logs(tenant_id,created_at desc);
