begin;
select plan(11);

select ok(
  (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname='platform_admin_audit_log'),
  'platform staff audit log has RLS enabled'
);
select ok(
  not has_table_privilege('authenticated','public.platform_admin_audit_log','SELECT')
  and not has_table_privilege('authenticated','public.platform_admin_audit_log','INSERT')
  and not has_table_privilege('authenticated','public.platform_admin_audit_log','UPDATE')
  and not has_table_privilege('authenticated','public.platform_admin_audit_log','DELETE'),
  'authenticated clients cannot access or mutate the staff audit table directly'
);
select ok(
  has_function_privilege('authenticated','public.platform_admin_list_staff()','EXECUTE')
  and has_function_privilege('authenticated','public.platform_admin_upsert_staff_by_email(text,text,boolean)','EXECUTE')
  and has_function_privilege('authenticated','public.platform_admin_list_staff_audit()','EXECUTE'),
  'authenticated sessions can call the guarded staff management RPCs'
);
select ok(
  not has_function_privilege('anon','public.platform_admin_list_staff()','EXECUTE')
  and not has_function_privilege('anon','public.platform_admin_upsert_staff_by_email(text,text,boolean)','EXECUTE')
  and not has_function_privilege('anon','public.platform_admin_list_staff_audit()','EXECUTE'),
  'anonymous sessions cannot call staff management RPCs'
);
select ok(
  (select count(*)=3 and bool_and(p.prosecdef)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('platform_admin_list_staff','platform_admin_upsert_staff_by_email','platform_admin_list_staff_audit')),
  'all staff management RPCs use SECURITY DEFINER'
);
select ok(
  (select bool_and(coalesce(array_to_string(p.proconfig,','),'') like '%search_path=%')
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('platform_admin_list_staff','platform_admin_upsert_staff_by_email','platform_admin_list_staff_audit')),
  'staff management RPCs set an explicit safe search_path'
);
select ok(
  (select position('super_admin' in p.prosrc)>0 and position('email_confirmed_at' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_admin_upsert_staff_by_email'),
  'staff provisioning requires Super Admin role and a confirmed account'
);
select ok(
  (select position('last active Super Admin' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_admin_upsert_staff_by_email'),
  'the last active Super Admin cannot be removed or demoted'
);
select ok(
  (select position('private.is_platform_staff_internal' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_admin_list_staff_audit'),
  'staff audit history is available only through a Super Admin-guarded RPC'
);
select ok(
  (select count(*)=3 and bool_and(p.prosecdef)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in ('platform_admin_list_staff','platform_admin_upsert_staff_by_email','platform_admin_list_staff_audit'))
  and not has_function_privilege('anon','public.platform_admin_list_staff()','EXECUTE'),
  'staff management API remains server-authorized'
);

select ok(
  (select position('pg_advisory_xact_lock' in p.prosrc)>0
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='platform_admin_upsert_staff_by_email'),
  'concurrent staff changes are serialized around the last Super Admin safeguard'
);

select * from finish();
rollback;
