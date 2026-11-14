-- Security hardening: server-enforced Order Booker catalogue, pricing, stock, tenant FK and GPS validation.
-- Apply only after review; this migration is intentionally prepared on a feature branch.

CREATE OR REPLACE FUNCTION private.booker_product_allowed(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_product_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_priority integer;
  v_branch_id uuid;
  v_warehouse_id uuid;
  v_stock numeric;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.products p
    WHERE p.id = p_product_id AND p.tenant_id = p_tenant_id AND p.is_active
  ) THEN
    RETURN false;
  END IF;

  SELECT e.branch_id INTO v_branch_id
  FROM public.employees e
  WHERE e.id = p_employee_id
    AND e.tenant_id = p_tenant_id
    AND e.employment_status = 'active';

  IF v_branch_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT min(
    CASE
      WHEN r.product_id = p_product_id THEN 1
      WHEN r.brand IS NOT NULL AND lower(r.brand) = lower(coalesce(p.brand, '')) THEN 2
      WHEN r.vendor_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.vendor_product_catalog vpc
        WHERE vpc.tenant_id = p_tenant_id
          AND vpc.product_id = p_product_id
          AND vpc.supplier_id = r.vendor_id
      ) THEN 3
    END
  ) INTO v_priority
  FROM public.booker_product_visibility r
  JOIN public.products p ON p.id = p_product_id AND p.tenant_id = p_tenant_id
  WHERE r.tenant_id = p_tenant_id
    AND r.employee_id = p_employee_id
    AND (
      r.product_id = p_product_id
      OR (r.brand IS NOT NULL AND lower(r.brand) = lower(coalesce(p.brand, '')))
      OR (r.vendor_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.vendor_product_catalog vpc
        WHERE vpc.tenant_id = p_tenant_id
          AND vpc.product_id = p_product_id
          AND vpc.supplier_id = r.vendor_id
      ))
    );

  -- Preserve the existing configuration convention: when no allow-rules exist,
  -- all otherwise-active products are eligible unless an explicit matching rule denies one.
  IF v_priority IS NULL THEN
    RETURN NOT EXISTS (
      SELECT 1 FROM public.booker_product_visibility r
      WHERE r.tenant_id = p_tenant_id
        AND r.employee_id = p_employee_id
        AND r.is_allowed = true
    );
  END IF;

  -- Specific-product rules override brand rules, which override vendor rules.
  IF NOT EXISTS (
    SELECT 1
    FROM public.booker_product_visibility r
    JOIN public.products p ON p.id = p_product_id AND p.tenant_id = p_tenant_id
    WHERE r.tenant_id = p_tenant_id
      AND r.employee_id = p_employee_id
      AND r.is_allowed = true
      AND CASE
        WHEN r.product_id = p_product_id THEN 1
        WHEN r.brand IS NOT NULL AND lower(r.brand) = lower(coalesce(p.brand, '')) THEN 2
        WHEN r.vendor_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.vendor_product_catalog vpc
          WHERE vpc.tenant_id = p_tenant_id
            AND vpc.product_id = p_product_id
            AND vpc.supplier_id = r.vendor_id
        ) THEN 3
      END = v_priority
  ) OR EXISTS (
    SELECT 1
    FROM public.booker_product_visibility r
    JOIN public.products p ON p.id = p_product_id AND p.tenant_id = p_tenant_id
    WHERE r.tenant_id = p_tenant_id
      AND r.employee_id = p_employee_id
      AND r.is_allowed = false
      AND CASE
        WHEN r.product_id = p_product_id THEN 1
        WHEN r.brand IS NOT NULL AND lower(r.brand) = lower(coalesce(p.brand, '')) THEN 2
        WHEN r.vendor_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.vendor_product_catalog vpc
          WHERE vpc.tenant_id = p_tenant_id
            AND vpc.product_id = p_product_id
            AND vpc.supplier_id = r.vendor_id
        ) THEN 3
      END = v_priority
  ) THEN
    RETURN false;
  END IF;

  -- Stock-required rules are enforced against the booker's assigned branch warehouse.
  IF EXISTS (
    SELECT 1
    FROM public.booker_product_visibility r
    JOIN public.products p ON p.id = p_product_id AND p.tenant_id = p_tenant_id
    WHERE r.tenant_id = p_tenant_id
      AND r.employee_id = p_employee_id
      AND r.is_allowed = true
      AND r.require_stock = true
      AND CASE
        WHEN r.product_id = p_product_id THEN 1
        WHEN r.brand IS NOT NULL AND lower(r.brand) = lower(coalesce(p.brand, '')) THEN 2
        WHEN r.vendor_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.vendor_product_catalog vpc
          WHERE vpc.tenant_id = p_tenant_id
            AND vpc.product_id = p_product_id
            AND vpc.supplier_id = r.vendor_id
        ) THEN 3
      END = v_priority
  ) THEN
    SELECT w.id INTO v_warehouse_id
    FROM public.warehouses w
    WHERE w.tenant_id = p_tenant_id
      AND w.branch_id = v_branch_id
      AND w.is_active = true
    ORDER BY w.is_default DESC, w.created_at
    LIMIT 1;

    IF v_warehouse_id IS NULL THEN
      RETURN false;
    END IF;

    SELECT coalesce(sum(sm.quantity_in - sm.quantity_out), 0)
      INTO v_stock
    FROM public.stock_movements sm
    WHERE sm.tenant_id = p_tenant_id
      AND sm.warehouse_id = v_warehouse_id
      AND sm.product_id = p_product_id;

    IF coalesce(v_stock, 0) <= 0 THEN
      RETURN false;
    END IF;
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION private.booker_product_allowed(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;

-- Pure Order Bookers must use the restricted RPC, not direct table reads.
-- Users who also hold a normal inventory/sales/purchasing role retain their normal access.
DROP POLICY IF EXISTS products_booker_direct_select_block ON public.products;
CREATE POLICY products_booker_direct_select_block ON public.products
AS RESTRICTIVE FOR SELECT TO authenticated
USING (
  NOT private.has_tenant_role_internal(tenant_id, ARRAY['order_booker']::text[])
  OR private.has_tenant_role_internal(tenant_id, ARRAY['owner','admin','manager','purchase','sales']::text[])
);

DROP POLICY IF EXISTS product_prices_booker_direct_select_block ON public.product_prices;
CREATE POLICY product_prices_booker_direct_select_block ON public.product_prices
AS RESTRICTIVE FOR SELECT TO authenticated
USING (
  NOT private.has_tenant_role_internal(tenant_id, ARRAY['order_booker']::text[])
  OR private.has_tenant_role_internal(tenant_id, ARRAY['owner','admin','manager','purchase','sales']::text[])
);

DROP POLICY IF EXISTS product_units_booker_direct_select_block ON public.product_units;
CREATE POLICY product_units_booker_direct_select_block ON public.product_units
AS RESTRICTIVE FOR SELECT TO authenticated
USING (
  NOT private.has_tenant_role_internal(tenant_id, ARRAY['order_booker']::text[])
  OR private.has_tenant_role_internal(tenant_id, ARRAY['owner','admin','manager','purchase','sales']::text[])
);

CREATE OR REPLACE FUNCTION public.get_booker_catalog(
  p_tenant_id uuid,
  p_customer_id uuid DEFAULT NULL
)
RETURNS TABLE (
  product_id uuid,
  sku text,
  barcode text,
  name text,
  brand text,
  sales_tax_rate numeric,
  unit_id uuid,
  conversion_to_base numeric,
  unit_name text,
  unit_symbol text,
  price numeric,
  min_quantity numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
BEGIN
  IF v_user_id IS NULL OR NOT public.has_tenant_role(p_tenant_id, ARRAY['order_booker']::text[]) THEN
    RAISE EXCEPTION 'Order Booker authorization is required.' USING ERRCODE = '42501';
  END IF;

  SELECT e.id INTO v_employee_id
  FROM public.employees e
  WHERE e.tenant_id = p_tenant_id
    AND e.user_id = v_user_id
    AND e.employment_status = 'active'
  LIMIT 1;

  IF v_employee_id IS NULL THEN
    RAISE EXCEPTION 'An active employee profile is required.' USING ERRCODE = '42501';
  END IF;

  IF p_customer_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.route_customers rc
    JOIN public.route_assignments ra
      ON ra.tenant_id = rc.tenant_id AND ra.route_id = rc.route_id
    WHERE rc.tenant_id = p_tenant_id
      AND rc.customer_id = p_customer_id
      AND ra.employee_id = v_employee_id
      AND ra.assigned_from <= current_date
      AND (ra.assigned_to IS NULL OR ra.assigned_to >= current_date)
  ) THEN
    RAISE EXCEPTION 'Customer is not assigned to your active route.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH selected_price_list AS (
    SELECT choice.price_list_id
    FROM (
      SELECT cpl.price_list_id, 1 AS priority
      FROM public.customer_price_lists cpl
      JOIN public.price_lists pl
        ON pl.id = cpl.price_list_id AND pl.tenant_id = cpl.tenant_id
      WHERE p_customer_id IS NOT NULL
        AND cpl.tenant_id = p_tenant_id
        AND cpl.customer_id = p_customer_id
        AND (pl.valid_from IS NULL OR pl.valid_from <= current_date)
        AND (pl.valid_to IS NULL OR pl.valid_to >= current_date)
      LIMIT 1
      UNION ALL
      SELECT pl.id, 2 AS priority
      FROM public.price_lists pl
      WHERE pl.tenant_id = p_tenant_id
        AND pl.is_default = true
        AND (pl.valid_from IS NULL OR pl.valid_from <= current_date)
        AND (pl.valid_to IS NULL OR pl.valid_to >= current_date)
        AND NOT EXISTS (
          SELECT 1
          FROM public.customer_price_lists cpl
          JOIN public.price_lists assigned_pl
            ON assigned_pl.id = cpl.price_list_id AND assigned_pl.tenant_id = cpl.tenant_id
          WHERE p_customer_id IS NOT NULL
            AND cpl.tenant_id = p_tenant_id
            AND cpl.customer_id = p_customer_id
            AND (assigned_pl.valid_from IS NULL OR assigned_pl.valid_from <= current_date)
            AND (assigned_pl.valid_to IS NULL OR assigned_pl.valid_to >= current_date)
        )
      ORDER BY priority, price_list_id
      LIMIT 1
    ) choice
  )
  SELECT
    p.id, p.sku, p.barcode, p.name, p.brand, p.sales_tax_rate,
    pu.unit_id, pu.conversion_to_base, u.name, u.symbol,
    pp.price, pp.min_quantity
  FROM public.products p
  JOIN public.product_units pu
    ON pu.tenant_id = p.tenant_id
   AND pu.product_id = p.id
   AND pu.is_sales_unit = true
  JOIN public.units_of_measure u
    ON u.tenant_id = pu.tenant_id
   AND u.id = pu.unit_id
  LEFT JOIN selected_price_list spl ON true
  LEFT JOIN public.product_prices pp
    ON pp.tenant_id = p.tenant_id
   AND pp.product_id = p.id
   AND pp.unit_id = pu.unit_id
   AND pp.price_list_id = spl.price_list_id
  WHERE p.tenant_id = p_tenant_id
    AND p.is_active = true
    AND private.booker_product_allowed(p_tenant_id, v_employee_id, p.id)
  ORDER BY p.name, pu.unit_id, pp.min_quantity;
END;
$$;

REVOKE ALL ON FUNCTION public.get_booker_catalog(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_booker_catalog(uuid,uuid) TO authenticated;

-- Enforce the same product visibility, stock and free-item rules at submission time.
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
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_branch_id uuid;
  v_warehouse_id uuid;
  v_price_list_id uuid;
  v_order_id uuid;
  v_order_number text;
  v_line jsonb;
  v_is_free boolean;
  v_product_id uuid;
  v_unit_id uuid;
  v_qty numeric;
  v_conversion numeric;
  v_unit_price numeric;
  v_tax_rate numeric;
  v_stock numeric;
  v_line_total numeric;
  v_subtotal numeric := 0;
  v_tax_total numeric := 0;
BEGIN
  IF v_user_id IS NULL OR p_client_request_id IS NULL THEN
    RAISE EXCEPTION 'Authentication and client request ID are required.';
  END IF;
  IF NOT public.has_tenant_role(p_tenant_id, ARRAY['order_booker']::text[]) THEN
    RAISE EXCEPTION 'Order Booker role is required for this company.' USING ERRCODE = '42501';
  END IF;

  SELECT so.id INTO v_order_id
  FROM public.sales_orders so
  WHERE so.tenant_id = p_tenant_id
    AND so.client_request_id = p_client_request_id
    AND so.created_by = v_user_id
    AND so.order_source = 'order_booker';
  IF v_order_id IS NOT NULL THEN
    RETURN v_order_id;
  END IF;

  IF jsonb_typeof(p_lines) <> 'array'
     OR jsonb_array_length(p_lines) = 0
     OR jsonb_array_length(p_lines) > 100 THEN
    RAISE EXCEPTION 'Order must contain between 1 and 100 lines.';
  END IF;
  IF length(coalesce(p_notes, '')) > 2000 THEN
    RAISE EXCEPTION 'Order notes cannot exceed 2000 characters.';
  END IF;

  SELECT e.id, e.branch_id INTO v_employee_id, v_branch_id
  FROM public.employees e
  WHERE e.tenant_id = p_tenant_id
    AND e.user_id = v_user_id
    AND e.employment_status = 'active'
  LIMIT 1;
  IF v_employee_id IS NULL OR v_branch_id IS NULL THEN
    RAISE EXCEPTION 'Your active employee profile and branch must be configured.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.route_assignments ra
    WHERE ra.tenant_id = p_tenant_id
      AND ra.employee_id = v_employee_id
      AND ra.route_id = p_route_id
      AND ra.assigned_from <= current_date
      AND (ra.assigned_to IS NULL OR ra.assigned_to >= current_date)
  ) THEN
    RAISE EXCEPTION 'This route is not assigned to your account.' USING ERRCODE = '42501';
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
    RAISE EXCEPTION 'This customer is not active on your assigned route.' USING ERRCODE = '42501';
  END IF;

  SELECT w.id INTO v_warehouse_id
  FROM public.warehouses w
  WHERE w.tenant_id = p_tenant_id
    AND w.branch_id = v_branch_id
    AND w.is_active = true
  ORDER BY w.is_default DESC, w.created_at
  LIMIT 1;
  IF v_warehouse_id IS NULL THEN
    RAISE EXCEPTION 'An active warehouse must be configured for your branch.';
  END IF;

  SELECT COALESCE(
    (
      SELECT cpl.price_list_id
      FROM public.customer_price_lists cpl
      JOIN public.price_lists pl
        ON pl.id = cpl.price_list_id AND pl.tenant_id = cpl.tenant_id
      WHERE cpl.tenant_id = p_tenant_id
        AND cpl.customer_id = p_customer_id
        AND (pl.valid_from IS NULL OR pl.valid_from <= current_date)
        AND (pl.valid_to IS NULL OR pl.valid_to >= current_date)
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
    RAISE EXCEPTION 'No valid customer/default sales price list is configured.';
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
    SELECT so.id INTO v_order_id
    FROM public.sales_orders so
    WHERE so.tenant_id = p_tenant_id
      AND so.client_request_id = p_client_request_id
      AND so.created_by = v_user_id
      AND so.order_source = 'order_booker';
    IF v_order_id IS NULL THEN
      RAISE EXCEPTION 'Client request ID is already in use.';
    END IF;
    RETURN v_order_id;
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines)
  LOOP
    v_is_free := coalesce((v_line->>'is_free_item')::boolean, false);
    IF v_is_free THEN
      RAISE EXCEPTION 'Free items require an approved promotion and cannot be submitted through this Booker workflow.';
    END IF;

    v_product_id := (v_line->>'product_id')::uuid;
    v_unit_id := (v_line->>'unit_id')::uuid;
    v_qty := (v_line->>'quantity')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 OR v_qty > 1000000 THEN
      RAISE EXCEPTION 'Order quantity must be greater than zero and within the allowed limit.';
    END IF;

    IF NOT private.booker_product_allowed(p_tenant_id, v_employee_id, v_product_id) THEN
      RAISE EXCEPTION 'This product is not authorized for your account or has no available stock.' USING ERRCODE = '42501';
    END IF;

    SELECT pu.conversion_to_base, pp.price, p.sales_tax_rate
      INTO v_conversion, v_unit_price, v_tax_rate
    FROM public.product_units pu
    JOIN public.products p
      ON p.id = pu.product_id AND p.tenant_id = pu.tenant_id
    JOIN public.product_prices pp
      ON pp.product_id = pu.product_id
     AND pp.unit_id = pu.unit_id
     AND pp.tenant_id = pu.tenant_id
    WHERE pu.tenant_id = p_tenant_id
      AND pu.product_id = v_product_id
      AND pu.unit_id = v_unit_id
      AND pu.is_sales_unit = true
      AND p.is_active = true
      AND pp.price_list_id = v_price_list_id
      AND pp.min_quantity <= v_qty
    ORDER BY pp.min_quantity DESC
    LIMIT 1;

    IF v_conversion IS NULL OR v_unit_price IS NULL THEN
      RAISE EXCEPTION 'A valid sales unit and price are missing for product %.', v_product_id;
    END IF;

    -- Do not allow an order quantity to exceed the stock in the booker's branch warehouse.
    IF EXISTS (
      SELECT 1
      FROM public.booker_product_visibility r
      JOIN public.products p ON p.id = v_product_id AND p.tenant_id = p_tenant_id
      WHERE r.tenant_id = p_tenant_id
        AND r.employee_id = v_employee_id
        AND r.is_allowed = true
        AND r.require_stock = true
        AND CASE
          WHEN r.product_id = v_product_id THEN 1
          WHEN r.brand IS NOT NULL AND lower(r.brand) = lower(coalesce(p.brand, '')) THEN 2
          WHEN r.vendor_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.vendor_product_catalog vpc
            WHERE vpc.tenant_id = p_tenant_id
              AND vpc.product_id = v_product_id
              AND vpc.supplier_id = r.vendor_id
          ) THEN 3
        END = (
          SELECT min(CASE
            WHEN r2.product_id = v_product_id THEN 1
            WHEN r2.brand IS NOT NULL AND lower(r2.brand) = lower(coalesce(p.brand, '')) THEN 2
            WHEN r2.vendor_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.vendor_product_catalog vpc2
              WHERE vpc2.tenant_id = p_tenant_id
                AND vpc2.product_id = v_product_id
                AND vpc2.supplier_id = r2.vendor_id
            ) THEN 3
          END)
          FROM public.booker_product_visibility r2
          WHERE r2.tenant_id = p_tenant_id
            AND r2.employee_id = v_employee_id
            AND (
              r2.product_id = v_product_id
              OR (r2.brand IS NOT NULL AND lower(r2.brand) = lower(coalesce(p.brand, '')))
              OR (r2.vendor_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.vendor_product_catalog vpc3
                WHERE vpc3.tenant_id = p_tenant_id
                  AND vpc3.product_id = v_product_id
                  AND vpc3.supplier_id = r2.vendor_id
              ))
            )
        )
    ) THEN
      SELECT coalesce(sum(sm.quantity_in - sm.quantity_out), 0)
        INTO v_stock
      FROM public.stock_movements sm
      WHERE sm.tenant_id = p_tenant_id
        AND sm.warehouse_id = v_warehouse_id
        AND sm.product_id = v_product_id;

      IF coalesce(v_stock, 0) < v_qty * v_conversion THEN
        RAISE EXCEPTION 'Insufficient available stock for product %.', v_product_id;
      END IF;
    END IF;

    v_line_total := round(v_qty * v_unit_price, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_tax_total := v_tax_total + round(v_line_total * coalesce(v_tax_rate,0) / 100, 2);

    INSERT INTO public.sales_order_lines (
      tenant_id, sales_order_id, product_id, unit_id, quantity,
      conversion_to_base, unit_price, tax_rate, discount_amount, line_total, invoice_note
    ) VALUES (
      p_tenant_id, v_order_id, v_product_id, v_unit_id, v_qty,
      v_conversion, v_unit_price, coalesce(v_tax_rate,0), 0, v_line_total, NULL
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

REVOKE ALL ON FUNCTION public.create_order_booker_order(uuid,uuid,uuid,uuid,date,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_order_booker_order(uuid,uuid,uuid,uuid,date,text,jsonb) TO authenticated;

-- Composite tenant/account reference: an expense cannot point at another tenant's COA row.
CREATE UNIQUE INDEX IF NOT EXISTS chart_of_accounts_tenant_id_id_uidx
  ON public.chart_of_accounts (tenant_id, id);

ALTER TABLE public.expenses
  DROP CONSTRAINT IF EXISTS expenses_expense_account_id_fkey;

ALTER TABLE public.expenses
  ADD CONSTRAINT expenses_tenant_expense_account_fkey
  FOREIGN KEY (tenant_id, expense_account_id)
  REFERENCES public.chart_of_accounts (tenant_id, id)
  ON DELETE RESTRICT
  NOT VALID;

ALTER TABLE public.expenses
  VALIDATE CONSTRAINT expenses_tenant_expense_account_fkey;

-- Validate both GPS coordinates together and constrain them to legal geographic ranges.
ALTER TABLE public.booker_visits
  ADD CONSTRAINT booker_visits_gps_pair_range_check
  CHECK (
    (latitude IS NULL AND longitude IS NULL)
    OR (
      latitude IS NOT NULL AND longitude IS NOT NULL
      AND latitude BETWEEN -90 AND 90
      AND longitude BETWEEN -180 AND 180
    )
  )
  NOT VALID;

ALTER TABLE public.booker_visits
  VALIDATE CONSTRAINT booker_visits_gps_pair_range_check;
