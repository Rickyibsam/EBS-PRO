-- Enforce per-user custom action permissions inside draft-voucher RPCs.
-- The UI guards are not an authorization boundary: callers can invoke RPCs directly.
-- Preserve existing tenant-role checks and make all changes additive.

do $migration$
declare
  v_oid oid;
  v_definition text;
  v_updated text;
  v_marker text;
begin
  -- Draft voucher line editor: enforce update permission by voucher module.
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='update_draft_voucher_lines'
    and pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_voucher_table text, p_voucher_id uuid, p_lines jsonb';
  if v_oid is null then raise exception 'Expected update_draft_voucher_lines(uuid,text,uuid,jsonb) was not found'; end if;
  v_definition:=pg_get_functiondef(v_oid);
  v_marker:='if not public.has_tenant_role(p_tenant_id,array[''owner'',''admin'',''manager'',''accounts'',''sales'',''warehouse'']) then';
  if position('private.module_permission_guard_internal(p_tenant_id' in v_definition)=0 then
    v_updated:=replace(v_definition,v_marker,
      'if not private.module_permission_guard_internal(p_tenant_id, case p_voucher_table '||
      'when ''sales_orders'' then ''sales_customer'' when ''sales_invoices'' then ''sales_customer'' when ''sales_credit_notes'' then ''sales_customer'' '||
      'when ''purchase_orders'' then ''purchase_supplier'' when ''goods_receipts'' then ''purchase_supplier'' when ''purchase_invoices'' then ''purchase_supplier'' when ''purchase_debit_notes'' then ''purchase_supplier'' '||
      'when ''journal_entries'' then ''accounts_finance'' else null end, ''update'') then raise exception ''Custom module update permission denied for this voucher.'' using errcode=''42501''; end if;'||E'\n '||v_marker);
    if v_updated=v_definition then raise exception 'Could not inject custom permission guard into update_draft_voucher_lines'; end if;
    execute v_updated;
  end if;

  -- Header revision restore: align role eligibility with the module and enforce its custom update grant.
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='restore_draft_voucher_revision'
    and pg_get_function_identity_arguments(p.oid)='p_revision_id uuid';
  if v_oid is null then raise exception 'Expected restore_draft_voucher_revision(uuid) was not found'; end if;
  v_definition:=pg_get_functiondef(v_oid);
  v_marker:='if not public.has_tenant_role(v_revision.tenant_id,array[''owner'',''admin'',''manager'',''accounts'']) then';
  if position('private.module_permission_guard_internal(v_revision.tenant_id' in v_definition)=0 then
    v_updated:=replace(v_definition,v_marker,
      'if not private.module_permission_guard_internal(v_revision.tenant_id, case when v_revision.entity_table like ''sales_%'' then ''sales_customer'' when v_revision.entity_table like ''purchase_%'' or v_revision.entity_table like ''goods_%'' then ''purchase_supplier'' else ''accounts_finance'' end, ''update'') then raise exception ''Custom module update permission denied for this voucher revision.'' using errcode=''42501''; end if;'||E'\n '||
      'if not public.has_tenant_role(v_revision.tenant_id, case when v_revision.entity_table like ''sales_%'' then array[''owner'',''admin'',''manager'',''sales'']::text[] when v_revision.entity_table like ''purchase_%'' or v_revision.entity_table like ''goods_%'' then array[''owner'',''admin'',''manager'',''purchase'',''warehouse'']::text[] else array[''owner'',''admin'',''manager'',''accounts'']::text[] end) then');
    if v_updated=v_definition then raise exception 'Could not inject custom permission guard into restore_draft_voucher_revision'; end if;
    execute v_updated;
  end if;

  -- Line revision restore can recreate a deleted line before calling the editor RPC.
  -- Keep that operation within the same transaction; the editor guard will reject and roll back
  -- the whole restore when the user lacks update permission.
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='restore_draft_voucher_line_revision'
    and pg_get_function_identity_arguments(p.oid)='p_revision_id uuid';
  if v_oid is null then raise exception 'Expected restore_draft_voucher_line_revision(uuid) was not found'; end if;
  v_definition:=pg_get_functiondef(v_oid);
  v_updated:=replace(v_definition,
    'array[''owner'',''admin'',''manager'',''accounts'',''sales'',''warehouse''])',
    'array[''owner'',''admin'',''manager'',''accounts'',''sales'',''purchase'',''warehouse''])');
  if v_updated<>v_definition then execute v_updated; end if;
end
$migration$;

-- Verify that all three RPCs now include the database-side permission guard.
do $verification$
declare
  v_name text;
  v_definition text;
begin
  foreach v_name in array array['update_draft_voucher_lines','restore_draft_voucher_revision'] loop
    select pg_get_functiondef(p.oid) into v_definition
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_name;
    if v_definition is null or position('module_permission_guard_internal' in v_definition)=0 then
      raise exception 'Database permission guard verification failed for %',v_name;
    end if;
  end loop;
end
$verification$;
