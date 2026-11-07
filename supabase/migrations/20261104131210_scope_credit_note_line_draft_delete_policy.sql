-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

drop policy if exists sales_credit_note_lines_delete on public.sales_credit_note_lines;
create policy sales_credit_note_lines_delete on public.sales_credit_note_lines
for delete to authenticated
using (
 public.has_tenant_role(tenant_id,array['owner','admin'])
 and exists (
  select 1 from public.sales_credit_notes n
  where n.id=sales_credit_note_lines.credit_note_id
    and n.tenant_id=sales_credit_note_lines.tenant_id
    and n.status='draft'
 )
);
