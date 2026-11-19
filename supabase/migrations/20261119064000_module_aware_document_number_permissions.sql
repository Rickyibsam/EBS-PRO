-- Keep document number allocation aligned with the per-user module permission matrix.
-- Explicit action overrides can grant a non-standard tenant role access to create
-- a voucher, while explicit denials for standard roles are still enforced.

create or replace function private.next_document_number_internal(
  p_tenant_id uuid,
  p_document_type text
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
  v_action text:='create';
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
    when 'sales_invoice' then v_prefix:='EBS-INV-';v_width:=6;v_module_key:='distribution_delivery';v_action:='update';
    when 'receipt' then v_prefix:='RC';v_width:=6;v_module_key:='accounts_finance';
    when 'journal_entry' then v_prefix:='EBS-JV-';v_width:=9;v_module_key:='accounts_finance';
    when 'payroll_run' then v_prefix:='EBS-PR-';v_width:=10;v_module_key:='hr_payroll';
    when 'stock_transfer' then v_prefix:='EBS-ST-';v_width:=9;v_module_key:='inventory';
    else raise exception 'Unsupported document type' using errcode='22023';
  end case;

  if v_user is null then
    raise exception 'Not authorized to allocate a document number' using errcode='42501';
  end if;

  v_role_allowed:=case
    when p_document_type='journal_entry' then
      public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts','warehouse','purchase','sales','cashier','hr'])
    else case v_module_key
      when 'sales_customer' then public.has_tenant_role(p_tenant_id,array['owner','admin','manager','sales','cashier'])
      when 'purchase_supplier' then public.has_tenant_role(p_tenant_id,array['owner','admin','manager','purchase','warehouse'])
      when 'distribution_delivery' then public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse'])
      when 'accounts_finance' then public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts','cashier'])
      when 'hr_payroll' then public.has_tenant_role(p_tenant_id,array['owner','admin','manager','accounts'])
      when 'inventory' then public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse'])
      else false end
  end;
  v_is_platform_owner:=public.has_tenant_role(p_tenant_id,array['owner','admin']);
  select exists(
    select 1 from public.tenant_user_module_permissions p
    where p.tenant_id=p_tenant_id and p.user_id=v_user and p.module_key=v_module_key
  ) into v_has_override;

  if p_document_type='journal_entry' then
    -- Source workflow RPCs enforce the relevant module permission before posting.
    if not v_role_allowed and not (
      private.module_permission_grant_internal(p_tenant_id,'accounts_finance','create')
      or private.module_permission_grant_internal(p_tenant_id,'purchase_supplier','update')
      or private.module_permission_grant_internal(p_tenant_id,'distribution_delivery','update')
      or private.module_permission_grant_internal(p_tenant_id,'inventory','update')
      or private.module_permission_grant_internal(p_tenant_id,'hr_payroll','update')
      or private.module_permission_grant_internal(p_tenant_id,'fixed_assets','update')
      or private.module_permission_grant_internal(p_tenant_id,'sales_customer','update')
    ) then
      raise exception 'Not authorized to allocate a journal number' using errcode='42501';
    end if;
  elsif not v_role_allowed then
    if not private.module_permission_grant_internal(p_tenant_id,v_module_key,v_action) then
      raise exception 'Not authorized to allocate a document number' using errcode='42501';
    end if;
  elsif not v_is_platform_owner and v_has_override
        and not private.module_permission_grant_internal(p_tenant_id,v_module_key,v_action) then
    raise exception 'Document creation is disabled for this user' using errcode='42501';
  end if;

  select b.id into v_branch_id
  from public.branches b
  where b.tenant_id=p_tenant_id and b.is_active
  order by b.is_default desc,b.created_at,b.id
  limit 1;
  if v_branch_id is null then
    raise exception 'Create an active branch before allocating document numbers' using errcode='23514';
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
