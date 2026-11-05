-- Restrict public-schema RPC execution to signed-in application users.
-- Preserve the existing authenticated execution surface while removing inherited
-- PUBLIC and direct anon grants. Trigger functions do not need client EXECUTE.
do $$
declare
  r record;
  v_authenticated_allowed boolean;
begin
  for r in
    select p.oid, n.nspname, p.proname,
           pg_get_function_identity_arguments(p.oid) as identity_args,
           p.prorettype = 'trigger'::regtype as is_trigger
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
  loop
    v_authenticated_allowed :=
      has_function_privilege('authenticated', r.oid, 'EXECUTE');

    execute format(
      'revoke execute on function %I.%I(%s) from public, anon',
      r.nspname, r.proname, r.identity_args
    );

    if v_authenticated_allowed and not r.is_trigger then
      execute format(
        'grant execute on function %I.%I(%s) to authenticated',
        r.nspname, r.proname, r.identity_args
      );
    end if;
  end loop;
end
$$;

-- Future postgres-owned public RPCs must receive explicit role grants.
alter default privileges for role postgres
  revoke execute on functions from public;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;
