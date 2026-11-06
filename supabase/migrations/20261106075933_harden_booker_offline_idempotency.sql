-- Make offline Order Booker retries idempotent even if mutable route/customer/price
-- configuration changes after the first request committed.
CREATE OR REPLACE FUNCTION public.create_order_booker_order(
  p_tenant_id uuid,
  p_route_id uuid,
  p_customer_id uuid,
  p_client_request_id uuid,
  p_required_delivery_date date,
  p_notes text,
  p_lines jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := (select auth.uid());
  v_employee_id uuid;
  v_branch_id uuid;
  v_warehouse_id uuid;
  v_price_list_id uuid;
  v_order_id uuid;
  v_order_number text;
  v_line jsonb;
  v_is_free boolean := false;
  v_product_id uuid;
  v_unit_id uuid;
  v_qty numeric;
  v_conversion numeric;
  v_unit_price numeric;
  v_tax_rate numeric;
  v_line_total numeric;
  v_subtotal numeric := 0;
  v_tax_total numeric := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_client_request_id IS NULL THEN
    RAISE EXCEPTION 'Client request ID is required';
  END IF;
  IF NOT has_tenant_role(p_tenant_id, ARRAY['order_booker']::text[]) THEN
    RAISE EXCEPTION 'Order Booker role is required for this company';
  END IF;

  -- Replay a committed request for the same user before checking mutable
  -- route, customer, employee, warehouse, or price-list configuration.
  SELECT so.id INTO v_order_id
  FROM public.sales_orders so
  WHERE so.tenant_id = p_tenant_id
    AND so.client_request_id = p_client_request_id
    AND so.created_by = v_user_id
    AND so.order_source = 'order_booker';
  IF v_order_id IS NOT NULL THEN
    RETURN v_order_id;
  END IF;

  IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'At least one order line is required';
  END IF;

  SELECT e.id, e.branch_id INTO v_employee_id, v_branch_id
  FROM public.employees e
  WHERE e.tenant_id = p_tenant_id
    AND e.user_id = v_user_id
    AND e.employment_status = 'active'
  LIMIT 1;
  IF v_employee_id IS NULL OR v_branch_id IS NULL THEN
    RAISE EXCEPTION 'Your active employee profile and branch must be configured by the administrator';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.route_assignments ra
    WHERE ra.tenant_id = p_tenant_id
      AND ra.employee_id = v_employee_id
      AND ra.route_id = p_route_id
      AND ra.assigned_from <= current_date
      AND (ra.assigned_to IS NULL OR ra.assigned_to >= current_date)
  ) THEN
    RAISE EXCEPTION 'This route is not assigned to your account';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.route_customers rc
    JOIN public.parties c ON c.id = rc.customer_id AND c.tenant_id = rc.tenant_id
    WHERE rc.tenant_id = p_tenant_id
      AND rc.route_id = p_route_id
      AND rc.customer_id = p_customer_id
      AND c.party_type IN ('customer','both')
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'This customer is not active on your assigned route';
  END IF;

  SELECT w.id INTO v_warehouse_id
  FROM public.warehouses w
  WHERE w.tenant_id = p_tenant_id
    AND w.branch_id = v_branch_id
    AND w.is_active = true
  ORDER BY w.is_default DESC, w.created_at
  LIMIT 1;
  IF v_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'An active warehouse must be configured for your branch';
  END IF;

  SELECT COALESCE(
    (
      SELECT cpl.price_list_id
      FROM public.customer_price_lists cpl
      JOIN public.price_lists cpl_pl
        ON cpl_pl.id = cpl.price_list_id AND cpl_pl.tenant_id = cpl.tenant_id
      WHERE cpl.tenant_id = p_tenant_id
        AND cpl.customer_id = p_customer_id
        AND (cpl_pl.valid_from IS NULL OR cpl_pl.valid_from <= current_date)
        AND (cpl_pl.valid_to IS NULL OR cpl_pl.valid_to >= current_date)
      LIMIT 1
    ),
    (
      SELECT pl.id
      FROM public.price_lists pl
      WHERE pl.tenant_id = p_tenant_id
        AND pl.is_default = true
        AND (pl.valid_from IS NULL OR pl.valid_from <= current_date)
        AND (pl.valid_to IS NULL OR pl.valid_to >= current_date)
      ORDER BY pl.created_at DESC
      LIMIT 1
    )
  ) INTO v_price_list_id;
  IF v_price_list_id IS NULL THEN
    RAISE EXCEPTION 'No valid customer/default sales price list is configured';
  END IF;

  PERFORM set_config('ebs.order_submission', p_client_request_id::text, true);
  v_order_number := 'OB-' || to_char(current_date, 'YYYYMMDD') || '-' ||
    upper(substr(replace(p_client_request_id::text,'-',''),1,12));

  INSERT INTO public.sales_orders (
    tenant_id, branch_id, warehouse_id, customer_id, route_id, booker_employee_id,
    order_number, order_source, order_date, required_delivery_date, status,
    subtotal, tax_total, discount_total, grand_total, notes, created_by, client_request_id
  ) VALUES (
    p_tenant_id, v_branch_id, v_warehouse_id, p_customer_id, p_route_id, v_employee_id,
    v_order_number, 'order_booker', now(), p_required_delivery_date, 'submitted',
    0, 0, 0, 0, p_notes, v_user_id, p_client_request_id
  )
  ON CONFLICT (tenant_id, client_request_id) WHERE client_request_id IS NOT NULL
  DO NOTHING
  RETURNING id INTO v_order_id;

  IF v_order_id IS NULL THEN
    -- A concurrent retry by this same user may have won the unique insert.
    -- Never return another user's order ID for a guessed/reused request key.
    SELECT so.id INTO v_order_id
    FROM public.sales_orders so
    WHERE so.tenant_id = p_tenant_id
      AND so.client_request_id = p_client_request_id
      AND so.created_by = v_user_id
      AND so.order_source = 'order_booker';
    IF v_order_id IS NULL THEN
      RAISE EXCEPTION 'Client request ID is already in use';
    END IF;
    RETURN v_order_id;
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines)
  LOOP
    v_is_free := COALESCE((v_line->>'is_free_item')::boolean,false);
    v_product_id := (v_line->>'product_id')::uuid;
    v_unit_id := (v_line->>'unit_id')::uuid;
    v_qty := (v_line->>'quantity')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Order quantity must be greater than zero';
    END IF;

    SELECT pu.conversion_to_base,
      CASE WHEN v_is_free THEN 0 ELSE pp.price END,
      CASE WHEN v_is_free THEN 0 ELSE p.sales_tax_rate END
    INTO v_conversion, v_unit_price, v_tax_rate
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id AND p.tenant_id = pu.tenant_id
    LEFT JOIN public.product_prices pp
      ON pp.product_id = pu.product_id
      AND pp.unit_id = pu.unit_id
      AND pp.tenant_id = pu.tenant_id
    WHERE pu.tenant_id = p_tenant_id
      AND pu.product_id = v_product_id
      AND pu.unit_id = v_unit_id
      AND pu.is_sales_unit = true
      AND p.is_active = true
      AND (v_is_free OR (pp.price_list_id = v_price_list_id AND pp.min_quantity <= v_qty))
    ORDER BY pp.min_quantity DESC
    LIMIT 1;

    IF v_conversion IS NULL OR v_unit_price IS NULL THEN
      RAISE EXCEPTION 'A valid sales unit and price are missing for product %', v_product_id;
    END IF;

    v_line_total := round(v_qty * v_unit_price, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_tax_total := v_tax_total + round(v_line_total * COALESCE(v_tax_rate,0) / 100, 2);

    INSERT INTO public.sales_order_lines (
      tenant_id, sales_order_id, product_id, unit_id, quantity,
      conversion_to_base, unit_price, tax_rate, discount_amount, line_total, invoice_note
    ) VALUES (
      p_tenant_id, v_order_id, v_product_id, v_unit_id, v_qty,
      v_conversion, v_unit_price, COALESCE(v_tax_rate,0), 0, v_line_total,
      CASE WHEN v_is_free THEN 'FREE ITEM' ELSE NULL END
    );
  END LOOP;

  UPDATE public.sales_orders
  SET subtotal = v_subtotal,
      tax_total = v_tax_total,
      grand_total = v_subtotal + v_tax_total,
      updated_at = now()
  WHERE id = v_order_id AND tenant_id = p_tenant_id;

  RETURN v_order_id;
END;
$function$;
