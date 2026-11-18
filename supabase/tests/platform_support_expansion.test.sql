begin;
select plan(19);

select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='platform_support_attachments'),
  'support attachment metadata has RLS enabled'
);
select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='platform_support_notifications'),
  'support notifications have RLS enabled'
);
select ok(
  exists(select 1 from storage.buckets where id='platform-support-attachments' and public=false),
  'support attachment bucket is private'
);
select ok(
  exists(select 1 from storage.buckets where id='platform-support-attachments' and file_size_limit=10485760),
  'support attachment bucket enforces a 10 MiB file limit'
);
select ok(
  exists(select 1 from pg_attribute where attrelid='public.platform_support_tickets'::regclass
         and attname='ticket_number' and attnotnull),
  'support tickets have a required public reference number'
);
select ok(
  exists(select 1 from pg_indexes where schemaname='public'
         and indexname='platform_support_tickets_ticket_number_uidx'),
  'support ticket reference numbers are unique'
);
select ok(
  exists(select 1 from pg_indexes where schemaname='public'
         and indexname='platform_support_tickets_sla_due_idx'),
  'open support tickets have an SLA due-date index'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='platform_support_notifications'
           and p.polname='platform_support_notifications_read_own'),
  'users can read only their own support notifications'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='platform_support_notifications'
           and p.polname='platform_support_notifications_mark_own'),
  'users can update only their own notification read state'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='platform_support_attachments'
           and p.polname='platform_support_attachments_read'),
  'support attachment metadata read policy exists'
);
select ok(
  exists(select 1 from pg_policy p join pg_class c on c.oid=p.polrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='platform_support_attachments'
           and p.polname='platform_support_attachments_insert'),
  'support attachment metadata insert policy exists'
);
select ok(
  exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
         and policyname='platform_support_files_read'),
  'private support objects have an authorized read policy'
);
select ok(
  exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
         and policyname='platform_support_files_insert'),
  'private support objects have an authorized upload policy'
);
select ok(
  exists(select 1 from pg_trigger where tgname='platform_support_ticket_sla' and not tgisinternal),
  'support ticket SLA trigger is installed'
);
select ok(
  exists(select 1 from pg_trigger where tgname='platform_support_ticket_notify' and not tgisinternal),
  'ticket creation and status notifications trigger is installed'
);
select ok(
  exists(select 1 from pg_trigger where tgname='platform_support_message_notify' and not tgisinternal),
  'support reply notifications trigger is installed'
);
select ok(
  not has_function_privilege('authenticated','private.notify_platform_support_ticket()','EXECUTE')
  and not has_function_privilege('authenticated','private.notify_platform_support_message()','EXECUTE'),
  'notification trigger functions cannot be called directly by authenticated users'
);
select ok(
  has_column_privilege('authenticated','public.platform_support_notifications','read_at','UPDATE')
  and not has_table_privilege('authenticated','public.platform_support_notifications','UPDATE'),
  'authenticated users can update notification read state only'
);
select ok(
  has_table_privilege('authenticated','public.platform_support_attachments','SELECT')
  and has_table_privilege('authenticated','public.platform_support_attachments','INSERT')
  and not has_table_privilege('authenticated','public.platform_support_attachments','UPDATE')
  and not has_table_privilege('authenticated','public.platform_support_attachments','DELETE'),
  'support attachment metadata is append-only for authenticated users'
);

select * from finish();
rollback;
