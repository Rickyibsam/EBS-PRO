-- Restore employee attendance schema and authenticated recording RPC to
-- clean migration replay. This mirrors the already deployed table contract.
CREATE TABLE IF NOT EXISTS public.employee_attendance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL,
  attendance_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('present','absent','late','half_day','leave','holiday')),
  check_in timestamptz,
  check_out timestamptz,
  notes text,
  recorded_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT employee_attendance_employee_tenant_fk
    FOREIGN KEY (tenant_id, employee_id) REFERENCES public.employees(tenant_id,id),
  CONSTRAINT employee_attendance_check_times
    CHECK (check_out IS NULL OR check_in IS NULL OR check_out >= check_in),
  CONSTRAINT employee_attendance_tenant_employee_date_uq
    UNIQUE (tenant_id, employee_id, attendance_date)
);
CREATE INDEX IF NOT EXISTS employee_attendance_tenant_date_idx
  ON public.employee_attendance(tenant_id, attendance_date DESC);
CREATE INDEX IF NOT EXISTS idx_fk_employee_attendance_employee
  ON public.employee_attendance(employee_id);
CREATE INDEX IF NOT EXISTS idx_fk_employee_attendance_recorded_by
  ON public.employee_attendance(recorded_by);

ALTER TABLE public.employee_attendance ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_attendance TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='employee_attendance_select') THEN
    CREATE POLICY employee_attendance_select ON public.employee_attendance FOR SELECT TO authenticated
    USING (
      public.has_tenant_role(tenant_id, ARRAY['owner','admin','manager','accounts']::text[])
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.id=employee_attendance.employee_id AND e.tenant_id=employee_attendance.tenant_id AND e.user_id=(SELECT auth.uid()))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='employee_attendance_insert') THEN
    CREATE POLICY employee_attendance_insert ON public.employee_attendance FOR INSERT TO authenticated
    WITH CHECK (
      public.has_tenant_role(tenant_id, ARRAY['owner','admin','manager']::text[])
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.id=employee_attendance.employee_id AND e.tenant_id=employee_attendance.tenant_id AND e.user_id=(SELECT auth.uid()))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='employee_attendance_update') THEN
    CREATE POLICY employee_attendance_update ON public.employee_attendance FOR UPDATE TO authenticated
    USING (
      public.has_tenant_role(tenant_id, ARRAY['owner','admin','manager']::text[])
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.id=employee_attendance.employee_id AND e.tenant_id=employee_attendance.tenant_id AND e.user_id=(SELECT auth.uid()))
    )
    WITH CHECK (
      public.has_tenant_role(tenant_id, ARRAY['owner','admin','manager']::text[])
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.id=employee_attendance.employee_id AND e.tenant_id=employee_attendance.tenant_id AND e.user_id=(SELECT auth.uid()))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_grant_select') THEN
    CREATE POLICY module_override_grant_select ON public.employee_attendance FOR SELECT TO authenticated
    USING (private.module_permission_grant_internal(tenant_id,'hr_payroll','view'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_grant_insert') THEN
    CREATE POLICY module_override_grant_insert ON public.employee_attendance FOR INSERT TO authenticated
    WITH CHECK (private.module_permission_grant_internal(tenant_id,'hr_payroll','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_grant_update') THEN
    CREATE POLICY module_override_grant_update ON public.employee_attendance FOR UPDATE TO authenticated
    USING (private.module_permission_grant_internal(tenant_id,'hr_payroll','update'))
    WITH CHECK (private.module_permission_grant_internal(tenant_id,'hr_payroll','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_grant_delete') THEN
    CREATE POLICY module_override_grant_delete ON public.employee_attendance FOR DELETE TO authenticated
    USING (private.module_permission_grant_internal(tenant_id,'hr_payroll','delete'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_guard_select') THEN
    CREATE POLICY module_override_guard_select ON public.employee_attendance FOR SELECT TO authenticated
    USING (private.module_permission_guard_internal(tenant_id,'hr_payroll','view'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_guard_insert') THEN
    CREATE POLICY module_override_guard_insert ON public.employee_attendance FOR INSERT TO authenticated
    WITH CHECK (private.module_permission_guard_internal(tenant_id,'hr_payroll','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_guard_update') THEN
    CREATE POLICY module_override_guard_update ON public.employee_attendance FOR UPDATE TO authenticated
    USING (private.module_permission_guard_internal(tenant_id,'hr_payroll','update'))
    WITH CHECK (private.module_permission_guard_internal(tenant_id,'hr_payroll','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='employee_attendance' AND policyname='module_override_guard_delete') THEN
    CREATE POLICY module_override_guard_delete ON public.employee_attendance FOR DELETE TO authenticated
    USING (private.module_permission_guard_internal(tenant_id,'hr_payroll','delete'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.record_employee_attendance(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_attendance_date date,
  p_status text,
  p_check_in timestamptz,
  p_check_out timestamptz,
  p_notes text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF NOT public.has_tenant_role(p_tenant_id,ARRAY['owner','admin','manager']::text[])
     AND NOT EXISTS (
       SELECT 1 FROM public.employees e
       WHERE e.id=p_employee_id AND e.tenant_id=p_tenant_id
         AND e.user_id=v_user AND e.employment_status='active'
     ) THEN
    RAISE EXCEPTION 'You can only record your own attendance.' USING ERRCODE='42501';
  END IF;
  IF p_status NOT IN ('present','absent','late','half_day','leave','holiday') THEN
    RAISE EXCEPTION 'Invalid attendance status.';
  END IF;
  IF p_check_in IS NOT NULL AND p_check_out IS NOT NULL AND p_check_out<p_check_in THEN
    RAISE EXCEPTION 'Check-out cannot be earlier than check-in.';
  END IF;
  INSERT INTO public.employee_attendance(
    tenant_id,employee_id,attendance_date,status,check_in,check_out,notes,recorded_by
  )
  SELECT p_tenant_id,e.id,p_attendance_date,p_status,p_check_in,p_check_out,p_notes,v_user
  FROM public.employees e
  WHERE e.id=p_employee_id AND e.tenant_id=p_tenant_id AND e.employment_status='active'
  ON CONFLICT(tenant_id,employee_id,attendance_date) DO UPDATE
    SET status=excluded.status,check_in=excluded.check_in,check_out=excluded.check_out,
        notes=excluded.notes,recorded_by=excluded.recorded_by,updated_at=now()
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Active employee was not found.'; END IF;
  RETURN jsonb_build_object('success',true,'attendance_id',v_id);
END;
$function$;
REVOKE ALL ON FUNCTION public.record_employee_attendance(uuid,uuid,date,text,timestamptz,timestamptz,text) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.record_employee_attendance(uuid,uuid,date,text,timestamptz,timestamptz,text) TO authenticated;
