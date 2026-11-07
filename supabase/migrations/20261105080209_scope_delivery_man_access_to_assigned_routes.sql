-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

DROP POLICY IF EXISTS delivery_shop_visits_select ON public.delivery_shop_visits;
DROP POLICY IF EXISTS delivery_shop_visits_insert ON public.delivery_shop_visits;
DROP POLICY IF EXISTS delivery_shop_visits_update ON public.delivery_shop_visits;
CREATE POLICY delivery_shop_visits_select ON public.delivery_shop_visits FOR SELECT TO authenticated
 USING (
  public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','sales','warehouse'])
  OR (public.has_tenant_role(tenant_id,ARRAY['delivery_man']) AND EXISTS (
    SELECT 1 FROM public.employees e
    WHERE e.id=delivery_shop_visits.delivery_man_employee_id
      AND e.tenant_id=delivery_shop_visits.tenant_id AND e.user_id=auth.uid()
  ))
 );
CREATE POLICY delivery_shop_visits_insert ON public.delivery_shop_visits FOR INSERT TO authenticated
 WITH CHECK (
  (public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','warehouse']) OR
   (public.has_tenant_role(tenant_id,ARRAY['delivery_man']) AND EXISTS (
    SELECT 1 FROM public.employees e
    WHERE e.id=delivery_shop_visits.delivery_man_employee_id
      AND e.tenant_id=delivery_shop_visits.tenant_id AND e.user_id=auth.uid()
   )))
  AND EXISTS (SELECT 1 FROM public.deliveries d WHERE d.id=delivery_shop_visits.delivery_id AND d.tenant_id=delivery_shop_visits.tenant_id AND d.delivery_man_employee_id=delivery_shop_visits.delivery_man_employee_id)
 );
CREATE POLICY delivery_shop_visits_update ON public.delivery_shop_visits FOR UPDATE TO authenticated
 USING (
  public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','warehouse'])
  OR (public.has_tenant_role(tenant_id,ARRAY['delivery_man']) AND EXISTS (
    SELECT 1 FROM public.employees e
    WHERE e.id=delivery_shop_visits.delivery_man_employee_id
      AND e.tenant_id=delivery_shop_visits.tenant_id AND e.user_id=auth.uid()
  ))
 )
 WITH CHECK (
  public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','warehouse'])
  OR (public.has_tenant_role(tenant_id,ARRAY['delivery_man']) AND EXISTS (
    SELECT 1 FROM public.employees e
    WHERE e.id=delivery_shop_visits.delivery_man_employee_id
      AND e.tenant_id=delivery_shop_visits.tenant_id AND e.user_id=auth.uid()
  ))
 );
DROP POLICY IF EXISTS delivery_man_read_assigned_deliveries ON public.deliveries;
CREATE POLICY delivery_man_read_assigned_deliveries ON public.deliveries FOR SELECT TO authenticated
 USING (public.has_tenant_role(tenant_id,ARRAY['delivery_man']) AND EXISTS (
  SELECT 1 FROM public.employees e WHERE e.id=deliveries.delivery_man_employee_id AND e.tenant_id=deliveries.tenant_id AND e.user_id=auth.uid()
 ));
DROP POLICY IF EXISTS delivery_man_read_assigned_delivery_lines ON public.delivery_lines;
CREATE POLICY delivery_man_read_assigned_delivery_lines ON public.delivery_lines FOR SELECT TO authenticated
 USING (public.has_tenant_role(tenant_id,ARRAY['delivery_man']) AND EXISTS (
  SELECT 1 FROM public.deliveries d JOIN public.employees e ON e.id=d.delivery_man_employee_id AND e.tenant_id=d.tenant_id
  WHERE d.id=delivery_lines.delivery_id AND d.tenant_id=delivery_lines.tenant_id AND e.user_id=auth.uid()
  AND public.has_tenant_role(d.tenant_id,ARRAY['delivery_man'])
  AND e.id=d.delivery_man_employee_id
 ));
