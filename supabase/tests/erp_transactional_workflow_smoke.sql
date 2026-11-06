-- EBS PRO transactional database smoke test.
-- Run only in the EBS-PRO Supabase SQL Editor.
-- All fixture rows are created inside one transaction and rolled back at the end.
-- No production business data is retained.

begin;

do $smoke$
declare
  v_user uuid;
  v_tenant_a uuid := gen_random_uuid();
  v_tenant_b uuid := gen_random_uuid();
  v_branch_a uuid := gen_random_uuid();
  v_branch_b uuid := gen_random_uuid();
  v_account_debit uuid := gen_random_uuid();
  v_account_credit uuid := gen_random_uuid();
  v_journal_ok uuid := gen_random_uuid();
  v_journal_bad uuid := gen_random_uuid();
  v_rejected boolean := false;
begin
  select user_id into v_user
  from public.tenant_memberships
  where role='owner' and is_active
  order by created_at
  limit 1;
  if v_user is null then raise exception 'Smoke test requires an active owner membership'; end if;
  perform set_config('request.jwt.claim.sub',v_user::text,true);

  insert into public.organizations(id,name,slug) values
    (v_tenant_a,'EBS Transaction Test A','ebs-tx-test-a-'||replace(v_tenant_a::text,'-','')),
    (v_tenant_b,'EBS Transaction Test B','ebs-tx-test-b-'||replace(v_tenant_b::text,'-',''));
  insert into public.tenant_memberships(tenant_id,user_id,role,is_active)
  values(v_tenant_a,v_user,'owner',true);

  insert into public.branches(id,tenant_id,name,code)
  values(v_branch_a,v_tenant_a,'Test Branch A','TX-A'),
        (v_branch_b,v_tenant_b,'Test Branch B','TX-B');

  -- Cross-tenant branch reference must be rejected by the composite FK.
  begin
    insert into public.warehouses(tenant_id,branch_id,name,code)
    values(v_tenant_a,v_branch_b,'Invalid Cross Tenant Warehouse','TX-WH-X');
  exception when foreign_key_violation then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'FAIL: cross-tenant branch reference was accepted'; end if;

  insert into public.chart_of_accounts(id,tenant_id,account_code,account_name,account_type)
  values
    (v_account_debit,v_tenant_a,'TX-1000','Smoke Test Cash','asset'),
    (v_account_credit,v_tenant_a,'TX-4000','Smoke Test Income','income');

  -- Balanced journal must post and preserve double-entry equality.
  insert into public.journal_entries(id,tenant_id,journal_number,entry_date,narration,status,created_by)
  values(v_journal_ok,v_tenant_a,'TX-JV-OK',current_date,'Transactional smoke test balanced journal','draft',v_user);
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values
    (v_tenant_a,v_journal_ok,v_account_debit,100,0,'Balanced debit'),
    (v_tenant_a,v_journal_ok,v_account_credit,0,100,'Balanced credit');
  perform public.post_journal_entry(v_journal_ok);
  if (select status from public.journal_entries where id=v_journal_ok)<>'posted' then
    raise exception 'FAIL: balanced journal did not post';
  end if;

  -- Unbalanced journal must be rejected and remain draft.
  insert into public.journal_entries(id,tenant_id,journal_number,entry_date,narration,status,created_by)
  values(v_journal_bad,v_tenant_a,'TX-JV-BAD',current_date,'Transactional smoke test unbalanced journal','draft',v_user);
  insert into public.journal_lines(tenant_id,journal_entry_id,account_id,debit,credit,memo)
  values
    (v_tenant_a,v_journal_bad,v_account_debit,100,0,'Unbalanced debit'),
    (v_tenant_a,v_journal_bad,v_account_credit,0,90,'Unbalanced credit');

  v_rejected:=false;
  begin
    perform public.post_journal_entry(v_journal_bad);
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then raise exception 'FAIL: unbalanced journal was accepted'; end if;
  if (select status from public.journal_entries where id=v_journal_bad)<>'draft' then
    raise exception 'FAIL: rejected journal changed state';
  end if;
end
$smoke$;

rollback;
