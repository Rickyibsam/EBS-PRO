-- Restore the immutable voucher revision log before the capture trigger below.
-- The hosted database has this table, but its original CREATE TABLE DDL was not
-- present in the checked-in migration history.

create table if not exists public.voucher_revisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.organizations(id) on delete cascade,
  entity_table text not null,
  entity_id uuid not null,
  action text not null check (action in ('updated','deleted')),
  before_data jsonb not null,
  after_data jsonb,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now()
);

create index if not exists idx_fk_voucher_revisions_c3cb0ece26
  on public.voucher_revisions(changed_by);
create index if not exists voucher_revisions_entity_idx
  on public.voucher_revisions(tenant_id,entity_table,entity_id,changed_at desc);

alter table public.voucher_revisions enable row level security;
drop policy if exists voucher_revisions_tenant_read on public.voucher_revisions;
create policy voucher_revisions_tenant_read on public.voucher_revisions
  for select to authenticated
  using (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts']::text[]));
drop policy if exists voucher_revisions_tenant_insert on public.voucher_revisions;
create policy voucher_revisions_tenant_insert on public.voucher_revisions
  for insert to authenticated
  with check (public.has_tenant_role(tenant_id,array['owner','admin','manager','accounts','sales','purchase','warehouse']::text[]));

revoke all on table public.voucher_revisions from anon,authenticated;
grant select,insert on table public.voucher_revisions to authenticated;

-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

create or replace function public.capture_draft_voucher_revision()
returns trigger language plpgsql
set search_path=pg_catalog,public,auth
as $$
declare
 v_before jsonb;v_after jsonb;v_tenant uuid;v_id uuid;v_status text;v_parent_id uuid;v_parent_table text;v_fk text;
begin
 v_before:=to_jsonb(old);
 v_tenant:=(v_before->>'tenant_id')::uuid;
 v_id:=(v_before->>'id')::uuid;
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

do $$
declare t text;
begin
 foreach t in array array['sales_order_lines','purchase_order_lines','journal_lines','goods_receipt_lines','purchase_invoice_lines','sales_invoice_lines','sales_credit_note_lines','purchase_debit_note_lines'] loop
  execute format('drop trigger if exists trg_capture_draft_voucher_revision on public.%I',t);
  execute format('create trigger trg_capture_draft_voucher_revision before update or delete on public.%I for each row execute function public.capture_draft_voucher_revision()',t);
 end loop;
end;
$$;
