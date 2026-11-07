-- Restored from the hosted Supabase migration ledger.
-- Original applied statement is preserved below.

create index if not exists expenses_expense_account_id_idx
  on public.expenses (expense_account_id)
  where expense_account_id is not null;
