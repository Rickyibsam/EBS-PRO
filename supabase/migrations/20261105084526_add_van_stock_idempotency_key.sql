-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

alter table public.van_stock_movements add column if not exists idempotency_key text; create unique index if not exists van_stock_movements_tenant_idempotency_uidx on public.van_stock_movements(tenant_id,idempotency_key) where idempotency_key is not null;
