-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

revoke all on function public.post_sales_credit_note(uuid) from public;
revoke all on function public.post_sales_credit_note(uuid) from anon;
grant execute on function public.post_sales_credit_note(uuid) to authenticated;
