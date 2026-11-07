-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

DROP POLICY IF EXISTS delivery_man_read_assigned_products ON public.products;
CREATE POLICY delivery_man_read_assigned_products ON public.products FOR SELECT TO authenticated
 USING (
  public.has_tenant_role(products.tenant_id,ARRAY['delivery_man'])
  AND EXISTS (
   SELECT 1
   FROM public.delivery_lines dl
   JOIN public.deliveries d ON d.id=dl.delivery_id AND d.tenant_id=dl.tenant_id
   JOIN public.employees e ON e.id=d.delivery_man_employee_id AND e.tenant_id=d.tenant_id
   WHERE dl.product_id=products.id
     AND dl.tenant_id=products.tenant_id
     AND e.user_id=auth.uid()
     AND d.status IN ('pending','picked','dispatched','delivered')
  )
 );
