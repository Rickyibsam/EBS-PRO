-- Restored from the hosted Supabase migration ledger.
-- Original applied statements are preserved below.

-- Prevent direct booker table writes from bypassing the validated RPC.
create or replace function public.guard_booker_order_insert()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.order_source = 'order_booker'
     and has_tenant_role(new.tenant_id, array['order_booker']::text[]) then
    if new.client_request_id is null
       or current_setting('ebs.order_submission', true) is distinct from new.client_request_id::text then
      raise exception 'Order Booker orders must be submitted through the validated order submission service';
    end if;
    if new.status <> 'submitted'
       or coalesce(new.subtotal,0) <> 0
       or coalesce(new.tax_total,0) <> 0
       or coalesce(new.discount_total,0) <> 0
       or coalesce(new.grand_total,0) <> 0 then
      raise exception 'Invalid initial Order Booker order values';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_booker_order_line_insert()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_request_id uuid;
  v_source text;
begin
  select so.client_request_id, so.order_source
    into v_request_id, v_source
  from public.sales_orders so
  where so.id = new.sales_order_id and so.tenant_id = new.tenant_id;

  if v_source = 'order_booker'
     and has_tenant_role(new.tenant_id, array['order_booker']::text[]) then
    if v_request_id is null
       or current_setting('ebs.order_submission', true) is distinct from v_request_id::text then
      raise exception 'Order Booker lines must be created through the validated order submission service';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_booker_order_insert on public.sales_orders;
create trigger guard_booker_order_insert
before insert on public.sales_orders
for each row execute function public.guard_booker_order_insert();

drop trigger if exists guard_booker_order_line_insert on public.sales_order_lines;
create trigger guard_booker_order_line_insert
before insert on public.sales_order_lines
for each row execute function public.guard_booker_order_line_insert();

drop policy if exists sales_orders_booker_submission_update on public.sales_orders;
create policy sales_orders_booker_submission_update on public.sales_orders
for update to authenticated
using (
  has_tenant_role(tenant_id, array['order_booker']::text[])
  and created_by = (select auth.uid())
  and order_source = 'order_booker'
  and status = 'submitted'
  and current_setting('ebs.order_submission', true) = client_request_id::text
)
with check (
  has_tenant_role(tenant_id, array['order_booker']::text[])
  and created_by = (select auth.uid())
  and order_source = 'order_booker'
  and status = 'submitted'
  and current_setting('ebs.order_submission', true) = client_request_id::text
);

create or replace function public.create_order_booker_order(
  p_tenant_id uuid,
  p_route_id uuid,
  p_customer_id uuid,
  p_client_request_id uuid,
  p_required_delivery_date date,
  p_notes text,
  p_lines jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_employee_id uuid;
  v_branch_id uuid;
  v_warehouse_id uuid;
  v_price_list_id uuid;
  v_order_id uuid;
  v_order_number text;
  v_line jsonb;
  v_product_id uuid;
  v_unit_id uuid;
  v_qty numeric;
  v_conversion numeric;
  v_unit_price numeric;
  v_tax_rate numeric;
  v_line_total numeric;
  v_subtotal numeric := 0;
  v_tax_total numeric := 0;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_client_request_id is null then raise exception 'Client request ID is required'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'At least one order line is required';
  end if;
  if not has_tenant_role(p_tenant_id, array['order_booker']::text[]) then
    raise exception 'Order Booker role is required for this company';
  end if;

  select e.id, e.branch_id into v_employee_id, v_branch_id
  from public.employees e
  where e.tenant_id = p_tenant_id and e.user_id = v_user_id
    and e.employment_status = 'active'
  limit 1;
  if v_employee_id is null or v_branch_id is null then
    raise exception 'Your active employee profile and branch must be configured by the administrator';
  end if;

  if not exists (
    select 1 from public.route_assignments ra
    where ra.tenant_id = p_tenant_id and ra.employee_id = v_employee_id
      and ra.route_id = p_route_id and ra.assigned_from <= current_date
      and (ra.assigned_to is null or ra.assigned_to >= current_date)
  ) then raise exception 'This route is not assigned to your account'; end if;

  if not exists (
    select 1 from public.route_customers rc
    join public.parties c on c.id = rc.customer_id and c.tenant_id = rc.tenant_id
    where rc.tenant_id = p_tenant_id and rc.route_id = p_route_id
      and rc.customer_id = p_customer_id
      and c.party_type in ('customer','both') and c.status = 'active'
  ) then raise exception 'This customer is not active on your assigned route'; end if;

  select w.id into v_warehouse_id
  from public.warehouses w
  where w.tenant_id = p_tenant_id and w.branch_id = v_branch_id and w.is_active = true
  order by w.is_default desc, w.created_at limit 1;
  if v_warehouse_id is null then raise exception 'An active warehouse must be configured for your branch'; end if;

  select coalesce(
    (select cpl.price_list_id from public.customer_price_lists cpl
     where cpl.tenant_id = p_tenant_id and cpl.customer_id = p_customer_id limit 1),
    (select pl.id from public.price_lists pl where pl.tenant_id = p_tenant_id
     and pl.is_default = true and (pl.valid_from is null or pl.valid_from <= current_date)
     and (pl.valid_to is null or pl.valid_to >= current_date)
     order by pl.created_at desc limit 1)
  ) into v_price_list_id;
  if v_price_list_id is null then raise exception 'No valid customer/default sales price list is configured'; end if;

  select so.id into v_order_id from public.sales_orders so
  where so.tenant_id = p_tenant_id and so.client_request_id = p_client_request_id;
  if v_order_id is not null then return v_order_id; end if;

  perform set_config('ebs.order_submission', p_client_request_id::text, true);
  v_order_number := 'OB-' || to_char(current_date, 'YYYYMMDD') || '-' || upper(substr(replace(p_client_request_id::text,'-',''),1,12));

  insert into public.sales_orders (
    tenant_id, branch_id, warehouse_id, customer_id, route_id, booker_employee_id,
    order_number, order_source, order_date, required_delivery_date, status,
    subtotal, tax_total, discount_total, grand_total, notes, created_by, client_request_id
  ) values (
    p_tenant_id, v_branch_id, v_warehouse_id, p_customer_id, p_route_id, v_employee_id,
    v_order_number, 'order_booker', now(), p_required_delivery_date, 'submitted',
    0, 0, 0, 0, p_notes, v_user_id, p_client_request_id
  )
  on conflict (tenant_id, client_request_id) where client_request_id is not null
  do nothing returning id into v_order_id;

  if v_order_id is null then
    select so.id into v_order_id from public.sales_orders so
    where so.tenant_id = p_tenant_id and so.client_request_id = p_client_request_id;
    return v_order_id;
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_unit_id := (v_line->>'unit_id')::uuid;
    v_qty := (v_line->>'quantity')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Order quantity must be greater than zero'; end if;

    select pu.conversion_to_base, pp.price, p.sales_tax_rate
      into v_conversion, v_unit_price, v_tax_rate
    from public.product_units pu
    join public.products p on p.id = pu.product_id and p.tenant_id = pu.tenant_id
    join public.product_prices pp on pp.product_id = pu.product_id
      and pp.unit_id = pu.unit_id and pp.tenant_id = pu.tenant_id
    where pu.tenant_id = p_tenant_id and pu.product_id = v_product_id
      and pu.unit_id = v_unit_id and pu.is_sales_unit = true and p.is_active = true
      and pp.price_list_id = v_price_list_id and pp.min_quantity <= v_qty
    order by pp.min_quantity desc limit 1;

    if v_conversion is null or v_unit_price is null then
      raise exception 'A valid sales unit and price are missing for product %', v_product_id;
    end if;

    v_line_total := round(v_qty * v_unit_price, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_tax_total := v_tax_total + round(v_line_total * coalesce(v_tax_rate,0) / 100, 2);

    insert into public.sales_order_lines (
      tenant_id, sales_order_id, product_id, unit_id, quantity,
      conversion_to_base, unit_price, tax_rate, discount_amount, line_total
    ) values (
      p_tenant_id, v_order_id, v_product_id, v_unit_id, v_qty,
      v_conversion, v_unit_price, coalesce(v_tax_rate,0), 0, v_line_total
    );
  end loop;

  update public.sales_orders set subtotal = v_subtotal, tax_total = v_tax_total,
    grand_total = v_subtotal + v_tax_total, updated_at = now()
  where id = v_order_id and tenant_id = p_tenant_id;

  return v_order_id;
end;
$$;

revoke all on function public.create_order_booker_order(uuid,uuid,uuid,uuid,date,text,jsonb) from public;
grant execute on function public.create_order_booker_order(uuid,uuid,uuid,uuid,date,text,jsonb) to authenticated;
