-- Super Admin-only staff provisioning and immutable platform staff audit history.

CREATE TABLE public.platform_admin_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  target_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK (action IN ('staff_created','staff_role_changed','staff_activated','staff_deactivated')),
  old_role text,
  new_role text NOT NULL CHECK (new_role IN ('super_admin','support_admin')),
  old_is_active boolean,
  new_is_active boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX platform_admin_audit_log_created_idx
  ON public.platform_admin_audit_log(created_at DESC);
CREATE INDEX platform_admin_audit_log_target_idx
  ON public.platform_admin_audit_log(target_user_id, created_at DESC);

ALTER TABLE public.platform_admin_audit_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.platform_admin_audit_log FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.platform_admin_list_staff()
RETURNS TABLE (
  user_id uuid,
  email text,
  role text,
  is_active boolean,
  created_at timestamptz,
  last_sign_in_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_platform_staff_internal(ARRAY['super_admin']::text[]) THEN
    RAISE EXCEPTION 'Super Admin authorization is required.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.id, u.email::text, pa.role, pa.is_active, pa.created_at, u.last_sign_in_at
  FROM public.platform_admins pa
  JOIN auth.users u ON u.id = pa.user_id
  ORDER BY pa.created_at DESC, u.email;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_admin_upsert_staff_by_email(
  p_email text,
  p_role text,
  p_is_active boolean DEFAULT true
)
RETURNS TABLE (user_id uuid, email text, role text, is_active boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_target uuid;
  v_old public.platform_admins%ROWTYPE;
  v_action text;
  v_other_super_admins integer;
BEGIN
  IF v_actor IS NULL OR NOT private.is_platform_staff_internal(ARRAY['super_admin']::text[]) THEN
    RAISE EXCEPTION 'Super Admin authorization is required.' USING ERRCODE = '42501';
  END IF;

  IF p_role NOT IN ('super_admin','support_admin') OR p_is_active IS NULL THEN
    RAISE EXCEPTION 'Choose a valid platform role and active state.' USING ERRCODE = '22023';
  END IF;

  SELECT u.id INTO v_target
  FROM auth.users u
  WHERE lower(u.email) = lower(btrim(p_email))
    AND u.email_confirmed_at IS NOT NULL;

  IF v_target IS NULL THEN
    RAISE EXCEPTION 'A registered account with a confirmed email address is required before platform access can be granted.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_old
  FROM public.platform_admins pa
  WHERE pa.user_id = v_target
  FOR UPDATE;

  IF FOUND THEN
    IF v_old.role = 'super_admin' AND v_old.is_active
       AND (p_role <> 'super_admin' OR NOT p_is_active) THEN
      SELECT count(*) INTO v_other_super_admins
      FROM public.platform_admins pa
      WHERE pa.is_active AND pa.role = 'super_admin' AND pa.user_id <> v_target;
      IF v_other_super_admins = 0 THEN
        RAISE EXCEPTION 'The last active Super Admin cannot be demoted or deactivated.' USING ERRCODE = '23514';
      END IF;
    END IF;

    v_action := CASE
      WHEN v_old.is_active IS DISTINCT FROM p_is_active AND NOT p_is_active THEN 'staff_deactivated'
      WHEN v_old.is_active IS DISTINCT FROM p_is_active AND p_is_active THEN 'staff_activated'
      WHEN v_old.role IS DISTINCT FROM p_role THEN 'staff_role_changed'
      ELSE 'staff_role_changed'
    END;

    UPDATE public.platform_admins
    SET role = p_role, is_active = p_is_active
    WHERE public.platform_admins.user_id = v_target;
  ELSE
    v_action := 'staff_created';
    INSERT INTO public.platform_admins(user_id, role, is_active, created_by)
    VALUES (v_target, p_role, p_is_active, v_actor);
  END IF;

  INSERT INTO public.platform_admin_audit_log
    (actor_id, target_user_id, action, old_role, new_role, old_is_active, new_is_active)
  VALUES
    (v_actor, v_target, v_action, v_old.role, p_role, v_old.is_active, p_is_active);

  RETURN QUERY
  SELECT pa.user_id, u.email::text, pa.role, pa.is_active
  FROM public.platform_admins pa
  JOIN auth.users u ON u.id = pa.user_id
  WHERE pa.user_id = v_target;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_admin_list_staff_audit()
RETURNS TABLE (
  id bigint,
  actor_email text,
  target_email text,
  action text,
  old_role text,
  new_role text,
  old_is_active boolean,
  new_is_active boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_platform_staff_internal(ARRAY['super_admin']::text[]) THEN
    RAISE EXCEPTION 'Super Admin authorization is required.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT l.id, actor.email::text, target.email::text, l.action,
         l.old_role, l.new_role, l.old_is_active, l.new_is_active, l.created_at
  FROM public.platform_admin_audit_log l
  JOIN auth.users actor ON actor.id = l.actor_id
  JOIN auth.users target ON target.id = l.target_user_id
  ORDER BY l.created_at DESC
  LIMIT 100;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_admin_list_staff() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_admin_upsert_staff_by_email(text,text,boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_admin_list_staff_audit() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_admin_list_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_admin_upsert_staff_by_email(text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_admin_list_staff_audit() TO authenticated;

COMMENT ON TABLE public.platform_admin_audit_log IS
  'Immutable audit trail for Super Admin platform staff provisioning and role changes.';
