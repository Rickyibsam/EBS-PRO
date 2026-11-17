-- Separate, server-authorized platform support workspace.
-- No platform admin is provisioned by this migration; the first Super Admin must be
-- explicitly bootstrapped by the project owner after verifying the target Auth user.

CREATE TABLE public.platform_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('super_admin', 'support_admin')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE TABLE public.platform_support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  subject text NOT NULL CHECK (length(btrim(subject)) BETWEEN 3 AND 180),
  category text NOT NULL CHECK (category IN ('technical','account','data','training','feature','other')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','critical')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','waiting_customer','resolved','closed')),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 3 AND 8000),
  resolution text,
  assigned_to uuid REFERENCES public.platform_admins(user_id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE TABLE public.platform_support_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ticket_id uuid NOT NULL REFERENCES public.platform_support_tickets(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 8000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX platform_support_tickets_tenant_status_idx
  ON public.platform_support_tickets (tenant_id, status, updated_at DESC);
CREATE INDEX platform_support_tickets_assigned_status_idx
  ON public.platform_support_tickets (assigned_to, status, updated_at DESC);
CREATE INDEX platform_support_messages_ticket_created_idx
  ON public.platform_support_messages (ticket_id, created_at);

ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_support_messages ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.platform_admins FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.platform_admins TO authenticated;
REVOKE ALL ON TABLE public.platform_support_tickets FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.platform_support_messages FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.platform_support_tickets TO authenticated;
GRANT SELECT, INSERT ON TABLE public.platform_support_messages TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.platform_support_messages_id_seq TO authenticated;

CREATE POLICY platform_admins_read_self
  ON public.platform_admins FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) AND is_active);

CREATE OR REPLACE FUNCTION private.is_platform_staff_internal(p_roles text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (SELECT auth.uid()) IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.platform_admins pa
      WHERE pa.user_id = (SELECT auth.uid())
        AND pa.is_active
        AND pa.role = ANY (coalesce(p_roles, ARRAY[]::text[]))
    );
$$;

REVOKE ALL ON FUNCTION private.is_platform_staff_internal(text[]) FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_platform_staff_internal(text[]) TO authenticated;

CREATE POLICY platform_support_tickets_staff_select
  ON public.platform_support_tickets FOR SELECT TO authenticated
  USING ((SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[])));

CREATE POLICY platform_support_tickets_staff_insert
  ON public.platform_support_tickets FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]))
    AND created_by = (SELECT auth.uid())
  );

CREATE POLICY platform_support_tickets_staff_update
  ON public.platform_support_tickets FOR UPDATE TO authenticated
  USING ((SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[])))
  WITH CHECK ((SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[])));

CREATE POLICY platform_support_messages_staff_select
  ON public.platform_support_messages FOR SELECT TO authenticated
  USING ((SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[])));

CREATE POLICY platform_support_messages_staff_insert
  ON public.platform_support_messages FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]))
    AND sender_id = (SELECT auth.uid())
  );

CREATE OR REPLACE FUNCTION public.platform_admin_me()
RETURNS TABLE (user_id uuid, role text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT pa.user_id, pa.role
  FROM public.platform_admins pa
  WHERE pa.user_id = (SELECT auth.uid())
    AND pa.is_active;
$$;

REVOKE ALL ON FUNCTION public.platform_admin_me() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_admin_me() TO authenticated;

CREATE OR REPLACE FUNCTION public.platform_admin_list_companies()
RETURNS TABLE (
  id uuid,
  name text,
  city text,
  contact_email text,
  contact_phone text,
  organization_status text,
  created_at timestamptz,
  member_count bigint,
  branch_count bigint,
  open_ticket_count bigint
)
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
  SELECT
    o.id,
    o.name,
    o.city,
    o.email,
    o.phone,
    o.status,
    o.created_at,
    (SELECT count(*) FROM public.tenant_memberships tm WHERE tm.tenant_id = o.id AND tm.is_active),
    (SELECT count(*) FROM public.branches b WHERE b.tenant_id = o.id),
    (SELECT count(*) FROM public.platform_support_tickets st
      WHERE st.tenant_id = o.id AND st.status NOT IN ('resolved','closed'))
  FROM public.organizations o
  ORDER BY o.created_at DESC, o.name;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_admin_list_companies() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_admin_list_companies() TO authenticated;

COMMENT ON TABLE public.platform_admins IS
  'Platform-level staff access; separate from tenant_memberships and never self-service.';
COMMENT ON TABLE public.platform_support_tickets IS
  'Platform support cases linked to a customer tenant; customers see their own tenant cases and platform staff see all cases.';
COMMENT ON TABLE public.platform_support_messages IS
  'Support conversation history; tenant members see their own company threads and platform staff see all support threads.';

-- Tenant members can create and read only their own company's support cases.
CREATE POLICY platform_support_tickets_tenant_select
  ON public.platform_support_tickets FOR SELECT TO authenticated
  USING ((SELECT private.is_tenant_member_internal(tenant_id)));

CREATE POLICY platform_support_tickets_tenant_insert
  ON public.platform_support_tickets FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT private.is_tenant_member_internal(tenant_id))
    AND created_by = (SELECT auth.uid())
  );

CREATE POLICY platform_support_messages_tenant_select
  ON public.platform_support_messages FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.platform_support_tickets st
      WHERE st.id = ticket_id
        AND private.is_tenant_member_internal(st.tenant_id)
    )
  );

CREATE POLICY platform_support_messages_tenant_insert
  ON public.platform_support_messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.platform_support_tickets st
      WHERE st.id = ticket_id
        AND private.is_tenant_member_internal(st.tenant_id)
    )
  );

-- A conversation reply updates the ticket's activity timestamp without granting
-- tenant users permission to update ticket status, priority or assignment.
CREATE OR REPLACE FUNCTION private.touch_platform_support_ticket()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.platform_support_tickets
  SET updated_at = now()
  WHERE id = NEW.ticket_id;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.touch_platform_support_ticket() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER platform_support_message_touch_ticket
AFTER INSERT ON public.platform_support_messages
FOR EACH ROW EXECUTE FUNCTION private.touch_platform_support_ticket();
