begin;

select plan(3);

select ok(
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname='platform_support_notifications'
      and c.conname='platform_support_notifications_tenant_ticket_fkey'
      and c.contype='f'
      and c.convalidated
      and cardinality(c.conkey)=2
  ),
  'support notification ticket reference is tenant-composite and validated'
);

select ok(
  exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname='platform_support_notifications'
      and c.conname='platform_support_notifications_ticket_tenant_required'
      and c.contype='c'
      and c.convalidated
  ),
  'notification with a ticket must include its tenant'
);

select is(
  (select count(*)::integer
   from public.platform_support_notifications n
   join public.platform_support_tickets t on t.id=n.ticket_id
   where n.tenant_id is distinct from t.tenant_id),
  0,
  'existing support notifications match their ticket tenant'
);

select * from finish();
rollback;
