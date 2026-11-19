-- Create stock transfer headers and lines atomically so a failed line insert
-- can never leave an empty draft voucher or consume a document sequence.

create or replace function public.create_stock_transfer(
  p_tenant_id uuid,
  p_from_warehouse_id uuid,
  p_to_warehouse_id uuid,
  p_transfer_date date,
  p_notes text,
  p_lines jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,public,private,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_number text;
  v_transfer_id uuid;
  v_requested integer;
  v_distinct integer;
  v_inserted integer;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if not (
    public.has_tenant_role(p_tenant_id,array['owner','admin','manager','warehouse'])
    or private.module_permission_grant_internal(p_tenant_id,'inventory','create')
  ) then
    raise exception 'Stock transfer creation permission required' using errcode='42501';
  end if;
  if p_from_warehouse_id is null or p_to_warehouse_id is null
     or p_from_warehouse_id=p_to_warehouse_id then
    raise exception 'Choose two different source and destination warehouses';
  end if;
  if p_transfer_date is null then
    raise exception 'Transfer date is required';
  end if;
  if not exists(select 1 from public.warehouses where id=p_from_warehouse_id and tenant_id=p_tenant_id and is_active)
     or not exists(select 1 from public.warehouses where id=p_to_warehouse_id and tenant_id=p_tenant_id and is_active) then
    raise exception 'Both warehouses must be active and belong to this company';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Transfer lines must be a JSON array';
  end if;
  if jsonb_array_length(p_lines)=0 then
    raise exception 'Add at least one product quantity';
  end if;

  v_requested:=jsonb_array_length(p_lines);
  select count(distinct product_id) into v_distinct
  from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity_base numeric);
  if v_requested<>v_distinct then
    raise exception 'Transfer lines contain duplicate or invalid products';
  end if;
  if exists(
    select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity_base numeric)
    where product_id is null or quantity_base is null or quantity_base<=0
  ) then
    raise exception 'Every transfer line requires a product and a positive quantity';
  end if;
  if exists(
    select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity_base numeric)
    left join public.products p on p.id=x.product_id and p.tenant_id=p_tenant_id
    where p.id is null or not p.is_active
  ) then
    raise exception 'Every selected product must be active and belong to this company';
  end if;

  v_number:=public.next_document_number(p_tenant_id,'stock_transfer');
  insert into public.stock_transfers(
    tenant_id,transfer_number,from_warehouse_id,to_warehouse_id,
    transfer_date,status,notes,created_by
  ) values (
    p_tenant_id,v_number,p_from_warehouse_id,p_to_warehouse_id,
    p_transfer_date,'draft',nullif(trim(p_notes),''),v_user
  ) returning id into v_transfer_id;

  insert into public.stock_transfer_lines(
    tenant_id,stock_transfer_id,product_id,quantity_base,unit_cost
  )
  select p_tenant_id,v_transfer_id,x.product_id,x.quantity_base,0
  from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity_base numeric);

  get diagnostics v_inserted=row_count;
  if v_inserted<>v_requested then
    raise exception 'Not all stock transfer lines were saved';
  end if;

  return jsonb_build_object(
    'success',true,'transfer_id',v_transfer_id,
    'transfer_number',v_number,'line_count',v_inserted,'status','draft'
  );
end
$function$;

revoke all on function public.create_stock_transfer(uuid,uuid,uuid,date,text,jsonb) from public,anon;
grant execute on function public.create_stock_transfer(uuid,uuid,uuid,date,text,jsonb) to authenticated;
