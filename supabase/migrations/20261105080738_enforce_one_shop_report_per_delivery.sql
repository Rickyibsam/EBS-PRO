-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

CREATE UNIQUE INDEX IF NOT EXISTS delivery_shop_visits_one_per_delivery_uidx ON public.delivery_shop_visits(tenant_id,delivery_id);
