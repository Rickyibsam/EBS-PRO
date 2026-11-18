-- Support escalation and immutable ticket event history.

ALTER TABLE public.platform_support_tickets
  ADD COLUMN escalation_level integer NOT NULL DEFAULT 0 CHECK (escalation_level >= 0),
  ADD COLUMN escalated_at timestamptz,
  ADD COLUMN escalated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN escalation_reason text;

ALTER TABLE public.platform_support_notifications
  DROP CONSTRAINT IF EXISTS platform_support_notifications_event_type_check;
ALTER TABLE public.platform_support_notifications
  ADD CONSTRAINT platform_support_notifications_event_type_check
  CHECK (event_type IN ('new_ticket','new_reply','status_changed','ticket_assigned','ticket_escalated'));

CREATE TABLE public.platform_support_ticket_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ticket_id uuid NOT NULL REFERENCES public.platform_support_tickets(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type text NOT NULL CHECK (event_type IN ('created','status_changed','assigned','resolution_updated','escalated')),
  from_value text,
  to_value text,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX platform_support_ticket_events_ticket_idx
  ON public.platform_support_ticket_events(ticket_id, created_at DESC);

ALTER TABLE public.platform_support_ticket_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.platform_support_ticket_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.platform_support_ticket_events TO authenticated;

CREATE POLICY platform_support_ticket_events_read
  ON public.platform_support_ticket_events FOR SELECT TO authenticated
  USING (
    (SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]))
    OR EXISTS (
      SELECT 1 FROM public.platform_support_tickets st
      WHERE st.id = ticket_id
        AND (SELECT private.is_tenant_member_internal(st.tenant_id))
    )
  );

CREATE OR REPLACE FUNCTION private.record_platform_support_ticket_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := (SELECT auth.uid());
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.platform_support_ticket_events
      (ticket_id, actor_id, event_type, to_value, reason)
    VALUES
      (NEW.id, v_actor, 'created', NEW.status, NEW.subject);
    RETURN NEW;
  END IF;

  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.platform_support_ticket_events
      (ticket_id, actor_id, event_type, from_value, to_value, reason)
    VALUES
      (NEW.id, v_actor, 'status_changed', OLD.status, NEW.status, NEW.resolution);
  END IF;

  IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN
    INSERT INTO public.platform_support_ticket_events
      (ticket_id, actor_id, event_type, from_value, to_value)
    VALUES
      (NEW.id, v_actor, 'assigned', OLD.assigned_to::text, NEW.assigned_to::text);
  END IF;

  IF OLD.resolution IS DISTINCT FROM NEW.resolution THEN
    INSERT INTO public.platform_support_ticket_events
      (ticket_id, actor_id, event_type, from_value, to_value)
    VALUES
      (NEW.id, v_actor, 'resolution_updated', OLD.resolution, NEW.resolution);
  END IF;

  IF OLD.escalation_level IS DISTINCT FROM NEW.escalation_level THEN
    INSERT INTO public.platform_support_ticket_events
      (ticket_id, actor_id, event_type, from_value, to_value, reason)
    VALUES
      (NEW.id, v_actor, 'escalated', OLD.escalation_level::text, NEW.escalation_level::text, NEW.escalation_reason);
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.record_platform_support_ticket_event() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS platform_support_ticket_event_history ON public.platform_support_tickets;
CREATE TRIGGER platform_support_ticket_event_history
AFTER INSERT OR UPDATE ON public.platform_support_tickets
FOR EACH ROW EXECUTE FUNCTION private.record_platform_support_ticket_event();

CREATE OR REPLACE FUNCTION public.platform_support_escalate_ticket(
  p_ticket_id uuid,
  p_reason text
)
RETURNS TABLE (ticket_id uuid, escalation_level integer, escalated_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ticket public.platform_support_tickets%ROWTYPE;
BEGIN
  IF (SELECT auth.uid()) IS NULL
     OR NOT private.is_platform_staff_internal(ARRAY['support_admin']::text[]) THEN
    RAISE EXCEPTION 'Support Admin authorization is required to escalate a ticket.' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 OR length(btrim(p_reason)) > 1000 THEN
    RAISE EXCEPTION 'Enter an escalation reason between 5 and 1000 characters.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_ticket
  FROM public.platform_support_tickets
  WHERE id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Support ticket was not found.' USING ERRCODE = 'P0002';
  END IF;

  IF v_ticket.status IN ('resolved','closed') THEN
    RAISE EXCEPTION 'Resolved or closed tickets cannot be escalated.' USING ERRCODE = '23514';
  END IF;

  UPDATE public.platform_support_tickets
  SET escalation_level = escalation_level + 1,
      escalated_at = now(),
      escalated_by = (SELECT auth.uid()),
      escalation_reason = btrim(p_reason),
      updated_at = now()
  WHERE id = p_ticket_id;

  RETURN QUERY
  SELECT st.id, st.escalation_level, st.escalated_at
  FROM public.platform_support_tickets st
  WHERE st.id = p_ticket_id;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_support_escalate_ticket(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_support_escalate_ticket(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION private.notify_platform_support_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.escalation_level IS DISTINCT FROM OLD.escalation_level THEN
    INSERT INTO public.platform_support_notifications
      (recipient_id, tenant_id, ticket_id, event_type, title, body)
    SELECT pa.user_id, NEW.tenant_id, NEW.id, 'ticket_escalated',
           'Escalated support ticket #' || NEW.ticket_number,
           left(COALESCE(NEW.escalation_reason, NEW.subject), 500)
    FROM public.platform_admins pa
    WHERE pa.is_active AND pa.role = 'super_admin';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_platform_support_escalation() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS platform_support_ticket_escalation_notify ON public.platform_support_tickets;
CREATE TRIGGER platform_support_ticket_escalation_notify
AFTER UPDATE OF escalation_level ON public.platform_support_tickets
FOR EACH ROW EXECUTE FUNCTION private.notify_platform_support_escalation();


CREATE OR REPLACE FUNCTION private.notify_platform_support_resolution()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.resolution IS DISTINCT FROM OLD.resolution AND NEW.resolution IS NOT NULL THEN
    INSERT INTO public.platform_support_notifications
      (recipient_id, tenant_id, ticket_id, event_type, title, body)
    SELECT tm.user_id, NEW.tenant_id, NEW.id, 'status_changed',
           'Resolution updated for support ticket #' || NEW.ticket_number,
           left(NEW.resolution, 500)
    FROM public.tenant_memberships tm
    WHERE tm.tenant_id = NEW.tenant_id AND tm.is_active
      AND ((SELECT auth.uid()) IS NULL OR tm.user_id <> (SELECT auth.uid()));
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_platform_support_resolution() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS platform_support_ticket_resolution_notify ON public.platform_support_tickets;
CREATE TRIGGER platform_support_ticket_resolution_notify
AFTER UPDATE OF resolution ON public.platform_support_tickets
FOR EACH ROW EXECUTE FUNCTION private.notify_platform_support_resolution();

COMMENT ON TABLE public.platform_support_ticket_events IS
  'Immutable, tenant-scoped history of support ticket creation, status, assignment, resolution and escalation events.';
