-- Platform staff agent directory and server-authorized ticket assignment.

CREATE OR REPLACE FUNCTION public.platform_support_list_agents()
RETURNS TABLE (user_id uuid, email text, role text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]) THEN
    RAISE EXCEPTION 'Platform support authorization is required.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT pa.user_id, u.email::text, pa.role
  FROM public.platform_admins pa
  JOIN auth.users u ON u.id = pa.user_id
  WHERE pa.is_active
  ORDER BY CASE pa.role WHEN 'support_admin' THEN 0 ELSE 1 END, u.email;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_support_assign_ticket(
  p_ticket_id uuid,
  p_assignee uuid
)
RETURNS TABLE (ticket_id uuid, assigned_to uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF (SELECT auth.uid()) IS NULL
     OR NOT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]) THEN
    RAISE EXCEPTION 'Platform support authorization is required.' USING ERRCODE = '42501';
  END IF;

  IF p_assignee IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.platform_admins pa
    WHERE pa.user_id = p_assignee AND pa.is_active
  ) THEN
    RAISE EXCEPTION 'Choose an active platform staff member.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.platform_support_tickets
  SET assigned_to = p_assignee, updated_at = now()
  WHERE id = p_ticket_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Support ticket was not found.' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  SELECT st.id, st.assigned_to
  FROM public.platform_support_tickets st
  WHERE st.id = p_ticket_id;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_support_list_agents() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.platform_support_assign_ticket(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_support_list_agents() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_support_assign_ticket(uuid,uuid) TO authenticated;
