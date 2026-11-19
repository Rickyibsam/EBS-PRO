-- Allocate voucher numbers against the selected branch rather than always
-- falling back to the tenant's default branch.

create or replace function private.next_document_number_internal(
  p_tenant_id uuid,
  p_document_type text,
  p_branch_id uuid
)
returns text
language plpgsql
security definer
set search_path=pg_catalog,public,private,auth
as $function$
declare
  v_n bigint;
  v_prefix text;
  v_width integer;
  v_branch_id uuid;
  v_user uuid:=auth.uid();
  v_module_key text;
  v_role_allowed boolean;
  v_is_platform_owner boolean;
  v_has_override boolean;
begin
  case p_document_type
    when 'sales_order' then v_prefix:='SO';v_width:=6;v_module_key:='sales_customer';
    when 'purchase_order' then v_prefix:='PO';v_width:=6;v_module_key:='purchase_supplier';
    when 'grn' then v_prefix:='GR';v_width:=5;v_module_key:='purchase_supplier';
    when 'credit_memo' then v_prefix:='CM';v_width:=6;v_module_key:='sales_customer';
    when 'delivery' then v_prefix:='DLV-';v_width:=5;v_module_key:='distribution_delivery';
    when 'sales_invoice' then v_prefix:='EBS-INV-';v_width:=6;v_module_key:='sales_customer';
    when 'receipt' then v_prefix:='RC';v_width:=6;v_module_key:='accounts_finance';
    when 'journal_entry' then v_prefix:='EBS-JV-';v_width:=9;v_module_key:='accounts_finance';
    when 'payroll_run' then v_prefix:='EBS-PR-';v_width:=10;v_module_key:='hr_payroll';
    when 'stock_transfer' then v_prefix:='EBS-ST-';v_width:=9;v_module_key:='inventory';
    else raise exception 'Unsupported document type' using errcode='22023';
  end case;

  if v_user is null then
    raise exception 'Not authorized to allocate a document number' using errcode='42501';
  end if;
  v_role_allowed:=public.has_tenant_role(
    p_tenant_id,array['owner','admin','manager','sales','purchase','warehouse','accounts']
  );
  v_is_platform_owner:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
  select exists(
    select 1 from public.tenant_user_module_permissions p
    where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key=v_module_key
  ) into v_has_override;

  if not v_role_allowed then
    if not private.module_permission_grant_internal(p_tenant_id,v_module_key,'create') then
      raise exception 'Not authorized to allocate a document number' using errcode='42501';
    end if;
  elsif not v_is_platform_owner and v_has_override
        and not private.module_permission_grant_internal(p_tenant_id,v_module_key,'create') then
    raise exception 'Document creation is disabled for this user' using errcode='42501';
  end if;

  if p_branch_id is null then
    select b.id into v_branch_id
    from public.branches b
    where b.tenant_id=p_tenant_id and b.is_active
    order by b.is_default desc,b.created_at,b.id
    limit 1;
  else
    select b.id into v_branch_id
    from public.branches b
    where b.id=p_branch_id and b.tenant_id=p_tenant_id and b.is_active;
  end if;
  if v_branch_id is null then
    raise exception 'Select an active branch in this company before allocating a document number' using errcode='23514';
  end if;

  insert into public.document_sequences(
    tenant_id,branch_id,document_type,prefix,next_number,padding
  ) values (
    p_tenant_id,v_branch_id,p_document_type,v_prefix,2,v_width
  )
  on conflict (tenant_id,document_type,branch_id)
  do update set next_number=public.document_sequences.next_number+1
  returning next_number-1,prefix,padding into v_n,v_prefix,v_width;

  return v_prefix||lpad(v_n::text,v_width,'0');
end
$function$;

revoke all on function private.next_document_number_internal(uuid,text,uuid) from public,anon;
grant execute on function private.next_document_number_internal(uuid,text,uuid) to authenticated;

create or replace function private.next_document_number_internal(
  p_tenant_id uuid,
  p_document_type text
)
returns text
language sql
security definer
set search_path=pg_catalog,public,private,auth
as $function$
  select private.next_document_number_internal(p_tenant_id,p_document_type,null::uuid)
$function$;

create or replace function public.next_document_number_for_branch(
  p_tenant_id uuid,
  p_document_type text,
  p_branch_id uuid
)
returns text
language sql
security invoker
set search_path=pg_catalog,public,private,auth
as $function$
  select private.next_document_number_internal(p_tenant_id,p_document_type,p_branch_id)
$function$;

revoke all on function public.next_document_number_for_branch(uuid,text,uuid) from public,anon;
grant execute on function public.next_document_number_for_branch(uuid,text,uuid) to authenticated;
