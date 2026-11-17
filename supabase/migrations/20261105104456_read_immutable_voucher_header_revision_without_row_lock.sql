-- Restore the header revision RPC before removing its obsolete row lock.
-- Its original CREATE FUNCTION statement was missing from the checked-in history.
create or replace function public.restore_draft_voucher_revision(p_revision_id uuid)
returns jsonb
language plpgsql
set search_path=pg_catalog,public,auth
as $function$
declare
 v_revision public.voucher_revisions%rowtype;
 v_table text;v_parent text;v_fk text;v_parent_id uuid;v_status text;v_cols text;v_updated integer;
begin
 if auth.uid() is null then raise exception 'Authentication required.'; end if;
 select * into v_revision from public.voucher_revisions where id=p_revision_id for update;
 if not found then raise exception 'Voucher revision was not found.'; end if;
 if not private.module_permission_guard_internal(v_revision.tenant_id,
   case when v_revision.entity_table like 'sales_%' then 'sales_customer'
        when v_revision.entity_table like 'purchase_%' or v_revision.entity_table like 'goods_%' then 'purchase_supplier'
        else 'accounts_finance' end,'update') then
  raise exception 'Custom module update permission denied for this voucher revision.' using errcode='42501';
 end if;
 if not public.has_tenant_role(v_revision.tenant_id,
   case when v_revision.entity_table like 'sales_%' then array['owner','admin','manager','sales']::text[]
        when v_revision.entity_table like 'purchase_%' or v_revision.entity_table like 'goods_%' then array['owner','admin','manager','purchase','warehouse']::text[]
        else array['owner','admin','manager','accounts']::text[] end) then
  raise exception 'You cannot restore this voucher revision.' using errcode='42501';
 end if;
 if v_revision.action<>'updated' then
  raise exception 'Only update revisions can be restored. Deleted records must be recreated through their source workflow.';
 end if;
 v_table:=v_revision.entity_table;
 if v_table not in ('sales_orders','purchase_orders','journal_entries','goods_receipts','purchase_invoices','sales_invoices','sales_credit_notes','purchase_debit_notes') then
  raise exception 'Unsupported voucher revision type.';
 end if;
 execute format('select status from public.%I where id=$1 and tenant_id=$2 for update',v_table)
   into v_status using v_revision.entity_id,v_revision.tenant_id;
 if v_status is distinct from 'draft' then
  raise exception 'Only a currently draft voucher can accept a restored revision.';
 end if;
 select string_agg(format('%I',column_name),',' order by ordinal_position) into v_cols
 from information_schema.columns
 where table_schema='public' and table_name=v_table
  and column_name not in ('id','tenant_id','created_at','created_by','updated_at','status','approved_by','posted_by','posted_at');
 if v_cols is null then raise exception 'No restorable fields were found for this voucher.'; end if;
 execute format('update public.%I t set (%s)=(select %s from jsonb_populate_record(null::public.%I,$1)) where t.id=$2 and t.tenant_id=$3',
   v_table,v_cols,v_cols,v_table)
 using v_revision.before_data,v_revision.entity_id,v_revision.tenant_id;
 get diagnostics v_updated=row_count;
 if v_updated<>1 then raise exception 'Revision restore did not update exactly one draft record.'; end if;
 return jsonb_build_object('success',true,'entity_table',v_table,'entity_id',v_revision.entity_id,'restored_revision_id',v_revision.id);
end;
$function$;

revoke all on function public.restore_draft_voucher_revision(uuid) from public,anon;
grant execute on function public.restore_draft_voucher_revision(uuid) to authenticated;

-- Voucher revision rows are immutable. Remove the unnecessary row update lock.
do $$
declare d text;
begin
 select pg_get_functiondef('public.restore_draft_voucher_revision(uuid)'::regprocedure) into d;
 d:=replace(d,'from public.voucher_revisions where id=p_revision_id for update;','from public.voucher_revisions where id=p_revision_id;');
 execute d;
end;
$$;
