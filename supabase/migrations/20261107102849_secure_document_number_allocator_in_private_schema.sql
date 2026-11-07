-- Keep the public RPC invoker-safe; isolate sequence writes in the non-exposed private schema.
create or replace function private.next_document_number_internal(
  p_tenant_id uuid,
  p_document_type text
) returns text
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_n bigint;
  v_prefix text;
  v_width integer;
  v_branch_id uuid;
  v_user uuid := auth.uid();
begin
  if v_user is null
     or not public.has_tenant_role(
       p_tenant_id,
       array['owner','admin','manager','sales','purchase','warehouse','accounts']
     ) then
    raise exception 'Not authorized to allocate a document number'
      using errcode = '42501';
  end if;

  case p_document_type
    when 'sales_order' then v_prefix := 'SO'; v_width := 6;
    when 'purchase_order' then v_prefix := 'PO'; v_width := 6;
    when 'grn' then v_prefix := 'GR'; v_width := 5;
    when 'credit_memo' then v_prefix := 'CM'; v_width := 6;
    when 'delivery' then v_prefix := 'DLV-'; v_width := 5;
    when 'sales_invoice' then v_prefix := 'EBS-INV-'; v_width := 6;
    when 'receipt' then v_prefix := 'RC'; v_width := 6;
    when 'journal_entry' then v_prefix := 'EBS-JV-'; v_width := 9;
    when 'payroll_run' then v_prefix := 'EBS-PR-'; v_width := 10;
    when 'stock_transfer' then v_prefix := 'EBS-ST-'; v_width := 9;
    else
      raise exception 'Unsupported document type'
        using errcode = '22023';
  end case;

  select b.id
    into v_branch_id
  from public.branches b
  where b.tenant_id = p_tenant_id
    and b.is_active
  order by b.is_default desc, b.created_at, b.id
  limit 1;

  if v_branch_id is null then
    raise exception 'Create an active branch before allocating document numbers'
      using errcode = '23514';
  end if;

  insert into public.document_sequences(
    tenant_id, branch_id, document_type, prefix, next_number, padding
  )
  values (
    p_tenant_id, v_branch_id, p_document_type, v_prefix, 2, v_width
  )
  on conflict (tenant_id, document_type, branch_id)
  do update
    set next_number = public.document_sequences.next_number + 1
  returning next_number - 1, prefix, padding
    into v_n, v_prefix, v_width;

  return v_prefix || lpad(v_n::text, v_width, '0');
end;
$$;

revoke all on function private.next_document_number_internal(uuid, text) from public, anon;
grant execute on function private.next_document_number_internal(uuid, text) to authenticated;

create or replace function public.next_document_number(
  p_tenant_id uuid,
  p_document_type text
) returns text
language sql
security invoker
set search_path = pg_catalog, public, private
as $$
  select private.next_document_number_internal(p_tenant_id, p_document_type);
$$;

revoke all on function public.next_document_number(uuid, text) from public, anon;
grant execute on function public.next_document_number(uuid, text) to authenticated;
