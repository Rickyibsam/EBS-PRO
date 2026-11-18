-- Support operations expansion: SLA targets, secure attachments and in-app notifications.
-- All customer access remains tenant-scoped; platform staff access is server-authorized.

CREATE SEQUENCE IF NOT EXISTS public.platform_support_ticket_number_seq;

ALTER TABLE public.platform_support_tickets
  ADD COLUMN IF NOT EXISTS ticket_number bigint,
  ADD COLUMN IF NOT EXISTS sla_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS first_response_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_customer_reply_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_staff_reply_at timestamptz,
  ADD COLUMN IF NOT EXISTS closed_at timestamptz;

UPDATE public.platform_support_tickets
SET ticket_number = nextval('public.platform_support_ticket_number_seq')
WHERE ticket_number IS NULL;

ALTER TABLE public.platform_support_tickets
  ALTER COLUMN ticket_number SET DEFAULT nextval('public.platform_support_ticket_number_seq'),
  ALTER COLUMN ticket_number SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS platform_support_tickets_ticket_number_uidx
  ON public.platform_support_tickets(ticket_number);

CREATE INDEX IF NOT EXISTS platform_support_tickets_sla_due_idx
  ON public.platform_support_tickets(sla_due_at)
  WHERE status NOT IN ('resolved','closed');

CREATE TABLE IF NOT EXISTS public.platform_support_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.platform_support_tickets(id) ON DELETE CASCADE,
  storage_path text NOT NULL UNIQUE,
  file_name text NOT NULL CHECK (length(btrim(file_name)) BETWEEN 1 AND 255),
  mime_type text NOT NULL CHECK (mime_type IN ('application/pdf','image/jpeg','image/png','image/webp','text/plain')),
  file_size bigint NOT NULL CHECK (file_size BETWEEN 1 AND 10485760),
  uploaded_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS platform_support_attachments_ticket_idx
  ON public.platform_support_attachments(ticket_id, created_at);

ALTER TABLE public.platform_support_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.platform_support_attachments FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.platform_support_attachments TO authenticated;

CREATE POLICY platform_support_attachments_read
  ON public.platform_support_attachments FOR SELECT TO authenticated
  USING (
    (SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]))
    OR EXISTS (
      SELECT 1 FROM public.platform_support_tickets st
      WHERE st.id = ticket_id
        AND (SELECT private.is_tenant_member_internal(st.tenant_id))
    )
  );

CREATE POLICY platform_support_attachments_insert
  ON public.platform_support_attachments FOR INSERT TO authenticated
  WITH CHECK (
    uploaded_by = (SELECT auth.uid())
    AND (
      (SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]))
      OR EXISTS (
        SELECT 1 FROM public.platform_support_tickets st
        WHERE st.id = ticket_id
          AND (SELECT private.is_tenant_member_internal(st.tenant_id))
      )
    )
  );

-- Private bucket: maximum 10 MiB, with an explicit allow-list of document/image types.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'platform-support-attachments',
  'platform-support-attachments',
  false,
  10485760,
  ARRAY['application/pdf','image/jpeg','image/png','image/webp','text/plain']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS platform_support_files_read ON storage.objects;
CREATE POLICY platform_support_files_read
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'platform-support-attachments'
    AND EXISTS (
      SELECT 1
      FROM public.platform_support_tickets st
      WHERE st.id = ((storage.foldername(name))[1])::uuid
        AND (
          (SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]))
          OR (SELECT private.is_tenant_member_internal(st.tenant_id))
        )
    )
  );

DROP POLICY IF EXISTS platform_support_files_insert ON storage.objects;
CREATE POLICY platform_support_files_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'platform-support-attachments'
    AND (storage.foldername(name))[2] = (SELECT auth.uid())::text
    AND EXISTS (
      SELECT 1
      FROM public.platform_support_tickets st
      WHERE st.id = ((storage.foldername(name))[1])::uuid
        AND (
          (SELECT private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]))
          OR (SELECT private.is_tenant_member_internal(st.tenant_id))
        )
    )
  );

CREATE TABLE IF NOT EXISTS public.platform_support_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  ticket_id uuid REFERENCES public.platform_support_tickets(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN ('new_ticket','new_reply','status_changed','ticket_assigned')),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 180),
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 500),
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS platform_support_notifications_recipient_idx
  ON public.platform_support_notifications(recipient_id, created_at DESC);

ALTER TABLE public.platform_support_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.platform_support_notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.platform_support_notifications TO authenticated;
GRANT UPDATE (read_at) ON TABLE public.platform_support_notifications TO authenticated;

CREATE POLICY platform_support_notifications_read_own
  ON public.platform_support_notifications FOR SELECT TO authenticated
  USING (recipient_id = (SELECT auth.uid()));

CREATE POLICY platform_support_notifications_mark_own
  ON public.platform_support_notifications FOR UPDATE TO authenticated
  USING (recipient_id = (SELECT auth.uid()))
  WITH CHECK (recipient_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION private.apply_platform_support_sla()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.priority IS DISTINCT FROM OLD.priority OR NEW.sla_due_at IS NULL THEN
    NEW.sla_due_at := now() + CASE NEW.priority
      WHEN 'critical' THEN interval '1 hour'
      WHEN 'high' THEN interval '4 hours'
      WHEN 'normal' THEN interval '24 hours'
      ELSE interval '72 hours'
    END;
  END IF;

  IF NEW.status = 'resolved' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    NEW.resolved_at := COALESCE(NEW.resolved_at, now());
  ELSIF NEW.status = 'closed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    NEW.closed_at := COALESCE(NEW.closed_at, now());
    NEW.resolved_at := COALESCE(NEW.resolved_at, now());
  ELSIF NEW.status NOT IN ('resolved','closed') THEN
    NEW.resolved_at := NULL;
    NEW.closed_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.apply_platform_support_sla() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS platform_support_ticket_sla ON public.platform_support_tickets;
CREATE TRIGGER platform_support_ticket_sla
BEFORE INSERT OR UPDATE OF priority, status, sla_due_at
ON public.platform_support_tickets
FOR EACH ROW EXECUTE FUNCTION private.apply_platform_support_sla();

CREATE OR REPLACE FUNCTION private.notify_platform_support_ticket()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_status_changed boolean := false;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    v_status_changed := OLD.status IS DISTINCT FROM NEW.status;
  END IF;

  IF TG_OP = 'INSERT' OR v_status_changed THEN
    IF TG_OP = 'INSERT' THEN
      INSERT INTO public.platform_support_notifications
        (recipient_id, tenant_id, ticket_id, event_type, title, body)
      SELECT pa.user_id, NEW.tenant_id, NEW.id, 'new_ticket',
             'New support ticket #' || NEW.ticket_number,
             left(NEW.subject || ' · ' || NEW.priority || ' priority', 500)
      FROM public.platform_admins pa
      WHERE pa.is_active AND pa.role IN ('super_admin','support_admin');
    ELSE
      INSERT INTO public.platform_support_notifications
        (recipient_id, tenant_id, ticket_id, event_type, title, body)
      SELECT tm.user_id, NEW.tenant_id, NEW.id, 'status_changed',
             'Support ticket #' || NEW.ticket_number || ' updated',
             left('Status changed to ' || replace(NEW.status, '_', ' '), 500)
      FROM public.tenant_memberships tm
      WHERE tm.tenant_id = NEW.tenant_id AND tm.is_active
        AND ((SELECT auth.uid()) IS NULL OR tm.user_id <> (SELECT auth.uid()));
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.assigned_to IS DISTINCT FROM NEW.assigned_to AND NEW.assigned_to IS NOT NULL THEN
    INSERT INTO public.platform_support_notifications
      (recipient_id, tenant_id, ticket_id, event_type, title, body)
    VALUES
      (NEW.assigned_to, NEW.tenant_id, NEW.id, 'ticket_assigned',
       'Ticket assigned to you: #' || NEW.ticket_number, left(NEW.subject, 500));
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_platform_support_ticket() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS platform_support_ticket_notify ON public.platform_support_tickets;
CREATE TRIGGER platform_support_ticket_notify
AFTER INSERT OR UPDATE ON public.platform_support_tickets
FOR EACH ROW EXECUTE FUNCTION private.notify_platform_support_ticket();

CREATE OR REPLACE FUNCTION private.notify_platform_support_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ticket public.platform_support_tickets%ROWTYPE;
  v_is_staff boolean;
BEGIN
  SELECT * INTO v_ticket
  FROM public.platform_support_tickets
  WHERE id = NEW.ticket_id;

  v_is_staff := private.is_platform_staff_internal(ARRAY['super_admin','support_admin']::text[]);

  IF v_is_staff THEN
    UPDATE public.platform_support_tickets
    SET first_response_at = COALESCE(first_response_at, now()),
        last_staff_reply_at = now(),
        updated_at = now()
    WHERE id = NEW.ticket_id;

    INSERT INTO public.platform_support_notifications
      (recipient_id, tenant_id, ticket_id, event_type, title, body)
    SELECT tm.user_id, v_ticket.tenant_id, v_ticket.id, 'new_reply',
           'Support replied to ticket #' || v_ticket.ticket_number,
           left(NEW.body, 500)
    FROM public.tenant_memberships tm
    WHERE tm.tenant_id = v_ticket.tenant_id AND tm.is_active
      AND tm.user_id <> NEW.sender_id;
  ELSE
    UPDATE public.platform_support_tickets
    SET last_customer_reply_at = now(),
        updated_at = now()
    WHERE id = NEW.ticket_id;

    IF v_ticket.assigned_to IS NOT NULL THEN
      INSERT INTO public.platform_support_notifications
        (recipient_id, tenant_id, ticket_id, event_type, title, body)
      VALUES
        (v_ticket.assigned_to, v_ticket.tenant_id, v_ticket.id, 'new_reply',
         'Customer replied to ticket #' || v_ticket.ticket_number, left(NEW.body, 500));
    ELSE
      INSERT INTO public.platform_support_notifications
        (recipient_id, tenant_id, ticket_id, event_type, title, body)
      SELECT pa.user_id, v_ticket.tenant_id, v_ticket.id, 'new_reply',
             'Customer replied to ticket #' || v_ticket.ticket_number, left(NEW.body, 500)
      FROM public.platform_admins pa
      WHERE pa.is_active AND pa.role IN ('super_admin','support_admin');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.notify_platform_support_message() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS platform_support_message_notify ON public.platform_support_messages;
CREATE TRIGGER platform_support_message_notify
AFTER INSERT ON public.platform_support_messages
FOR EACH ROW EXECUTE FUNCTION private.notify_platform_support_message();

COMMENT ON TABLE public.platform_support_attachments IS
  'Private support ticket attachments. Files are stored in the private platform-support-attachments bucket.';
COMMENT ON TABLE public.platform_support_notifications IS
  'In-app support notifications. Authenticated users can read and mark only their own notifications.';
