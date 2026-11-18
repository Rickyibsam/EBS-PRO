-- Restore employee leave requests to clean migration replay. The deployed
-- schema contains this table, but the original migration history omitted it.
CREATE TABLE IF NOT EXISTS public.employee_leaves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL,
  leave_type text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  total_days numeric NOT NULL CHECK (total_days > 0),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  reason text,
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT employee_leaves_employee_tenant_fk
    FOREIGN KEY (tenant_id,employee_id) REFERENCES public.employees(tenant_id,id),
  CONSTRAINT employee_leaves_date_range_check CHECK (end_date >= start_date)
);
CREATE INDEX IF NOT EXISTS employee_leaves_tenant_status_idx
  ON public.employee_leaves(tenant_id,status,start_date);
CREATE INDEX IF NOT EXISTS idx_fk_employee_leaves_13a5899efe
  ON public.employee_leaves(employee_id);
CREATE INDEX IF NOT EXISTS idx_fk_employee_leaves_2908ce7908
  ON public.employee_leaves(approved_by);
CREATE INDEX IF NOT EXISTS idx_fk_employee_leaves_703ee2afde
  ON public.employee_leaves(created_by);
CREATE INDEX IF NOT EXISTS tenant_fk_idx_b810db57a8c4f67e8897
  ON public.employee_leaves(tenant_id,employee_id);

ALTER TABLE public.employee_leaves ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.employee_leaves TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='employee_leaves_select') THEN
    CREATE POLICY employee_leaves_select ON public.employee_leaves FOR SELECT TO authenticated
    USING (
      public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager','accounts']::text[])
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.id=employee_leaves.employee_id AND e.tenant_id=employee_leaves.tenant_id AND e.user_id=(SELECT auth.uid()))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='employee_leaves_insert') THEN
    CREATE POLICY employee_leaves_insert ON public.employee_leaves FOR INSERT TO authenticated
    WITH CHECK (
      public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager']::text[])
      OR (created_by=(SELECT auth.uid()) AND EXISTS (
        SELECT 1 FROM public.employees e WHERE e.id=employee_leaves.employee_id AND e.tenant_id=employee_leaves.tenant_id AND e.user_id=(SELECT auth.uid())
      ))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='employee_leaves_update') THEN
    CREATE POLICY employee_leaves_update ON public.employee_leaves FOR UPDATE TO authenticated
    USING (public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager']::text[]))
    WITH CHECK (public.has_tenant_role(tenant_id,ARRAY['owner','admin','manager']::text[]));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_grant_select') THEN
    CREATE POLICY module_override_grant_select ON public.employee_leaves FOR SELECT TO authenticated
    USING (private.module_permission_grant_internal(tenant_id,'hr_payroll','view'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_grant_insert') THEN
    CREATE POLICY module_override_grant_insert ON public.employee_leaves FOR INSERT TO authenticated
    WITH CHECK (private.module_permission_grant_internal(tenant_id,'hr_payroll','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_grant_update') THEN
    CREATE POLICY module_override_grant_update ON public.employee_leaves FOR UPDATE TO authenticated
    USING (private.module_permission_grant_internal(tenant_id,'hr_payroll','update'))
    WITH CHECK (private.module_permission_grant_internal(tenant_id,'hr_payroll','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_grant_delete') THEN
    CREATE POLICY module_override_grant_delete ON public.employee_leaves FOR DELETE TO authenticated
    USING (private.module_permission_grant_internal(tenant_id,'hr_payroll','delete'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_guard_select') THEN
    CREATE POLICY module_override_guard_select ON public.employee_leaves FOR SELECT TO authenticated
    USING (private.module_permission_guard_internal(tenant_id,'hr_payroll','view'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_guard_insert') THEN
    CREATE POLICY module_override_guard_insert ON public.employee_leaves FOR INSERT TO authenticated
    WITH CHECK (private.module_permission_guard_internal(tenant_id,'hr_payroll','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_guard_update') THEN
    CREATE POLICY module_override_guard_update ON public.employee_leaves FOR UPDATE TO authenticated
    USING (private.module_permission_guard_internal(tenant_id,'hr_payroll','update'))
    WITH CHECK (private.module_permission_guard_internal(tenant_id,'hr_payroll','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_leaves' AND policyname='module_override_guard_delete') THEN
    CREATE POLICY module_override_guard_delete ON public.employee_leaves FOR DELETE TO authenticated
    USING (private.module_permission_guard_internal(tenant_id,'hr_payroll','delete'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.decide_employee_leave(p_leave_id uuid,p_decision text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE v_leave public.employee_leaves%rowtype;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT * INTO v_leave FROM public.employee_leaves WHERE id=p_leave_id FOR UPDATE;
  IF NOT FOUND OR NOT public.has_tenant_role(v_leave.tenant_id,ARRAY['owner','admin','manager']::text[]) THEN
    RAISE EXCEPTION 'You cannot approve this leave request.' USING ERRCODE='42501';
  END IF;
  IF v_leave.status<>'pending' OR p_decision NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'Only pending leave requests can be decided.';
  END IF;
  UPDATE public.employee_leaves
  SET status=p_decision,approved_by=auth.uid(),approved_at=now()
  WHERE id=p_leave_id AND tenant_id=v_leave.tenant_id;
  RETURN jsonb_build_object('success',true,'status',p_decision);
END;
$function$;
REVOKE ALL ON FUNCTION public.decide_employee_leave(uuid,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.decide_employee_leave(uuid,text) TO authenticated;
