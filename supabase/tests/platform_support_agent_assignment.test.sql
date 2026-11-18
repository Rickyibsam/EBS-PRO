begin;
select plan(8);

select ok(
  has_function_privilege('authenticated','public.platform_support_list_agents()','EXECUTE')
  and has_function_privilege('authenticated','public.platform_support_assign_ticket(uuid,uuid)','EXECUTE'),
  'authenticated platform sessions can call the support agent RPCs'
);
select ok(
  not has_function_privilege('anon','public.platform_support_list_agents()','EXECUTE')
  and not has_function_privilege('anon','public.platform_support_assign_ticket(uuid,uuid)','EXECUTE'),
  'anonymous users cannot call the support agent RPCs'
);
select ok(
  (select p.prosecdef and position('super_admin' in p.prosrc)>0 and position('support_admin' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_support_list_agents'),
  'agent directory requires an active platform staff role'
);
select ok(
  (select p.prosecdef and position('private.is_platform_staff_internal' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_support_assign_ticket'),
  'ticket assignment is server-authorized'
);
select ok(
  (select position('pa.is_active' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_support_list_agents'),
  'only active platform staff appear in the agent directory'
);
select ok(
  (select position('Choose an active platform staff member' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_support_assign_ticket'),
  'ticket assignment rejects inactive or non-platform accounts'
);
select ok(
  exists(select 1 from pg_trigger where tgname='platform_support_ticket_event_history' and not tgisinternal)
  and exists(select 1 from pg_trigger where tgname='platform_support_ticket_notify' and not tgisinternal),
  'assignment updates create history and notification records'
);
select ok(
  (select bool_and(coalesce(array_to_string(p.proconfig,','),'') like '%search_path=%')
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('platform_support_list_agents','platform_support_assign_ticket')),
  'support agent RPCs use explicit safe search paths'
);

select * from finish();
rollback;
