-- Explicit deny-all policy documents that the internal counter table is trigger-only.
drop policy if exists master_code_sequences_deny_all on public.master_code_sequences;
create policy master_code_sequences_deny_all
on public.master_code_sequences
for all
to public
using (false)
with check (false);
