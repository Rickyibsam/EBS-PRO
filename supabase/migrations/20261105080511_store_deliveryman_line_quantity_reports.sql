-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

ALTER TABLE public.delivery_shop_visits
 ADD COLUMN IF NOT EXISTS line_quantities jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.delivery_shop_visits
 ADD CONSTRAINT delivery_shop_visits_line_quantities_array_check
 CHECK (jsonb_typeof(line_quantities)='array');
