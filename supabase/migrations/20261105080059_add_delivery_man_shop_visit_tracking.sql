-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

ALTER TABLE public.tenant_memberships DROP CONSTRAINT IF EXISTS tenant_memberships_role_check;
ALTER TABLE public.tenant_memberships ADD CONSTRAINT tenant_memberships_role_check
 CHECK (role = ANY (ARRAY['owner','admin','manager','accounts','purchase','sales','order_booker','delivery_man','warehouse','cashier','viewer']::text[]));

CREATE TABLE IF NOT EXISTS public.delivery_shop_visits (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL REFERENCES public.organizations(id),
 delivery_id uuid NOT NULL,
 delivery_man_employee_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 visit_at timestamptz NOT NULL DEFAULT now(),
 visit_status text NOT NULL CHECK (visit_status = ANY (ARRAY['delivered','short_delivered','not_available','market_return','refused']::text[])),
 shops_visited integer NOT NULL DEFAULT 1 CHECK (shops_visited >= 0),
 notes text,
 latitude numeric,
 longitude numeric,
 created_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT delivery_shop_visits_delivery_fk FOREIGN KEY (delivery_id,tenant_id) REFERENCES public.deliveries(id,tenant_id),
 CONSTRAINT delivery_shop_visits_employee_fk FOREIGN KEY (delivery_man_employee_id,tenant_id) REFERENCES public.employees(id,tenant_id),
 CONSTRAINT delivery_shop_visits_customer_fk FOREIGN KEY (customer_id,tenant_id) REFERENCES public.parties(id,tenant_id)
);
CREATE INDEX IF NOT EXISTS delivery_shop_visits_tenant_date_idx ON public.delivery_shop_visits(tenant_id,visit_at DESC);
CREATE INDEX IF NOT EXISTS delivery_shop_visits_employee_date_idx ON public.delivery_shop_visits(tenant_id,delivery_man_employee_id,visit_at DESC);
ALTER TABLE public.delivery_shop_visits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS delivery_shop_visits_select ON public.delivery_shop_visits;
DROP POLICY IF EXISTS delivery_shop_visits_insert ON public.delivery_shop_visits;
DROP POLICY IF EXISTS delivery_shop_visits_update ON public.delivery_shop_visits;
CREATE POLICY delivery_shop_visits_select ON public.delivery_shop_visits FOR SELECT TO authenticated
 USING (public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','sales','warehouse','delivery_man']));
CREATE POLICY delivery_shop_visits_insert ON public.delivery_shop_visits FOR INSERT TO authenticated
 WITH CHECK (public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','warehouse','delivery_man']) AND EXISTS (
  SELECT 1 FROM public.deliveries d WHERE d.id=delivery_id AND d.tenant_id=tenant_id
 ));
CREATE POLICY delivery_shop_visits_update ON public.delivery_shop_visits FOR UPDATE TO authenticated
 USING (public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','warehouse','delivery_man']))
 WITH CHECK (public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','warehouse','delivery_man']));
