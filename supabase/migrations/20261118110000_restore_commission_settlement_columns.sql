-- Restore commission settlement and return-recovery fields that exist in the
-- hosted schema but were absent from the original checked-in migration history.
-- Additive and safe for existing production rows.
ALTER TABLE public.sales_incentive_accruals
  ADD COLUMN IF NOT EXISTS settled_amount numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS return_adjustment_due numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS additional_due numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS settled_by uuid;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_incentive_accruals'::regclass AND conname='sales_incentive_accruals_settled_amount_check') THEN
    ALTER TABLE public.sales_incentive_accruals ADD CONSTRAINT sales_incentive_accruals_settled_amount_check CHECK (settled_amount >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_incentive_accruals'::regclass AND conname='sales_incentive_accruals_return_adjustment_due_check') THEN
    ALTER TABLE public.sales_incentive_accruals ADD CONSTRAINT sales_incentive_accruals_return_adjustment_due_check CHECK (return_adjustment_due >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_incentive_accruals'::regclass AND conname='sales_incentive_accruals_additional_due_check') THEN
    ALTER TABLE public.sales_incentive_accruals ADD CONSTRAINT sales_incentive_accruals_additional_due_check CHECK (additional_due >= 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.sales_incentive_accruals'::regclass AND conname='sales_incentive_accruals_settled_by_fkey') THEN
    ALTER TABLE public.sales_incentive_accruals ADD CONSTRAINT sales_incentive_accruals_settled_by_fkey FOREIGN KEY (settled_by) REFERENCES auth.users(id);
  END IF;
END $$;
