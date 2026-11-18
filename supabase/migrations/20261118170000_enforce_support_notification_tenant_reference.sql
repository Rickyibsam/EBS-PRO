-- Enforce tenant consistency between support notifications and their ticket.
-- Existing production rows were checked before this migration: zero tenant mismatches
-- and zero orphaned ticket references were found.

create unique index if not exists platform_support_tickets_tenant_id_id_uidx
  on public.platform_support_tickets(tenant_id,id);

alter table public.platform_support_notifications
  add constraint platform_support_notifications_ticket_tenant_required
  check (ticket_id is null or tenant_id is not null) not valid;

alter table public.platform_support_notifications
  validate constraint platform_support_notifications_ticket_tenant_required;

alter table public.platform_support_notifications
  drop constraint if exists platform_support_notifications_ticket_id_fkey;

alter table public.platform_support_notifications
  add constraint platform_support_notifications_tenant_ticket_fkey
  foreign key (tenant_id,ticket_id)
  references public.platform_support_tickets(tenant_id,id)
  on delete cascade
  not valid;

alter table public.platform_support_notifications
  validate constraint platform_support_notifications_tenant_ticket_fkey;

create index if not exists platform_support_notifications_tenant_ticket_idx
  on public.platform_support_notifications(tenant_id,ticket_id)
  where ticket_id is not null;
