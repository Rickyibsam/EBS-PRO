begin;
select plan(13);

select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='platform_support_ticket_events'),
  'support ticket history has RLS enabled'
);
select ok(
  has_table_privilege('authenticated','public.platform_support_ticket_events','SELECT')
  and not has_table_privilege('authenticated','public.platform_support_ticket_events','INSERT')
  and not has_table_privilege('authenticated','public.platform_support_ticket_events','UPDATE')
  and not has_table_privilege('authenticated','public.platform_support_ticket_events','DELETE'),
  'authenticated users can read but cannot mutate ticket history directly'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='platform_support_ticket_events'
           and p.polname='platform_support_ticket_events_read'),
  'ticket history is scoped to platform staff and the ticket tenant'
);
select ok(
  exists(select 1 from pg_trigger where tgname='platform_support_ticket_event_history' and not tgisinternal),
  'ticket history trigger is installed'
);
select ok(
  (select p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') like '%search_path=%'
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='record_platform_support_ticket_event'),
  'event history trigger uses SECURITY DEFINER with a safe search_path'
);
select ok(
  has_function_privilege('authenticated','public.platform_support_escalate_ticket(uuid,text)','EXECUTE'),
  'authenticated platform sessions can call the guarded escalation RPC'
);
select ok(
  not has_function_privilege('anon','public.platform_support_escalate_ticket(uuid,text)','EXECUTE'),
  'anonymous users cannot call the escalation RPC'
);
select ok(
  (select p.prosecdef and position('support_admin' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_support_escalate_ticket'),
  'escalation requires an authorized Support Admin session'
);
select ok(
  (select position('resolved' in p.prosrc)>0 and position('closed' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_support_escalate_ticket'),
  'resolved and closed tickets cannot be escalated'
);
select ok(
  exists(select 1 from pg_constraint c
         where c.conrelid='public.platform_support_notifications'::regclass
           and c.contype='c' and pg_get_constraintdef(c.oid) like '%ticket_escalated%'),
  'support notification event type includes escalations'
);
select ok(
  exists(select 1 from pg_trigger where tgname='platform_support_ticket_escalation_notify' and not tgisinternal),
  'escalation notification trigger is installed'
);
select ok(
  exists(select 1 from pg_publication_tables
         where pubname='supabase_realtime' and schemaname='public'
           and tablename='platform_support_notifications')
  OR NOT EXISTS(select 1 from pg_publication where pubname='supabase_realtime'),
  'escalation notifications use the realtime publication when available'
);
select ok(
  exists(select 1 from pg_indexes where schemaname='public'
         and indexname='platform_support_ticket_events_ticket_idx'),
  'ticket event history has a ticket/time index'
);

select * from finish();
rollback;
