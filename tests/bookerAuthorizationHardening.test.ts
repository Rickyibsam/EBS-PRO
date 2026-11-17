import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261114135000_harden_booker_authorization_and_tenant_integrity.sql", import.meta.url),
  "utf8"
);
const moduleSource = await readFile(new URL("../src/BookerOrderModule.tsx", import.meta.url), "utf8");

test("Booker client loads product, unit and price data only through the restricted catalogue RPC", () => {
  assert.ok(moduleSource.includes('db.rpc("get_booker_catalog"'));
  assert.doesNotMatch(moduleSource, /db\.from\("(products|product_prices|product_units|vendor_product_catalog)"\)/);
});

test("restricted Booker catalogue omits product cost and sale-cost fields", () => {
  const returnsBlock = migration.match(/RETURNS TABLE \(([\s\S]*?)\)\s*LANGUAGE plpgsql/i)?.[1] || "";
  assert.ok(returnsBlock.includes("sales_tax_rate"));
  assert.ok(returnsBlock.includes("price_list_id"));
  assert.doesNotMatch(returnsBlock, /cost_price|purchase_cost|sale_price/i);
  assert.ok(migration.includes("private.booker_product_allowed"));
  const allowFunction = migration.match(/CREATE OR REPLACE FUNCTION private\.booker_product_allowed\([\s\S]*?END;\s*\$\$;/)?.[0] || "";
  assert.ok(allowFunction.includes("AND r.is_allowed = false"));
  assert.ok(allowFunction.includes("vpc.supplier_id = r.vendor_id"));
  assert.ok(allowFunction.includes("IF EXISTS ("));
  assert.ok(allowFunction.includes("RETURN false;"));
});

test("Booker direct table reads are blocked for pure Booker role", () => {
  for (const policy of [
    "products_booker_direct_select_block",
    "product_prices_booker_direct_select_block",
    "product_units_booker_direct_select_block"
  ]) {
    assert.ok(migration.includes(policy));
  }
  assert.ok(migration.includes("AS RESTRICTIVE FOR SELECT TO authenticated"));
  assert.ok(migration.includes("REVOKE ALL ON FUNCTION public.get_booker_stock_balances(uuid)"));
  assert.ok(migration.includes("ARRAY['owner','admin','manager','purchase','sales','warehouse']::text[]"));
  assert.doesNotMatch(migration, /ARRAY\['owner','admin','manager','purchase','sales','warehouse','cashier','viewer'\]::text\[\]/);
});

test("order submission enforces product visibility, branch stock and denies unapproved free items", () => {
  assert.ok(migration.includes("private.booker_product_allowed(p_tenant_id, v_employee_id, v_product_id)"));
  assert.ok(migration.includes("Insufficient available stock for product"));
  assert.ok(migration.includes("Free items require an approved promotion"));
  assert.ok(migration.includes("p_lines IS NULL"));
  assert.ok(migration.includes("jsonb_typeof(p_lines) IS DISTINCT FROM 'array'"));
});

test("catalogue and order submission select the same customer/default price list deterministically", () => {
  assert.ok(migration.includes("ORDER BY priority, selection_created_at DESC NULLS LAST, price_list_id"));
  assert.ok(migration.includes("ORDER BY pl.created_at DESC, pl.id"));
  assert.ok(migration.includes("ORDER BY cpl.price_list_id"));
});

test("tenant expense account foreign key and Booker GPS range constraints are composite and validated", () => {
  assert.ok(migration.includes("FOREIGN KEY (tenant_id, expense_account_id)"));
  assert.ok(migration.includes("REFERENCES public.chart_of_accounts (tenant_id, id)"));
  assert.ok(migration.includes("booker_visits_gps_pair_range_check"));
  assert.ok(migration.includes("latitude BETWEEN -90 AND 90"));
  assert.ok(migration.includes("longitude BETWEEN -180 AND 180"));
  assert.ok(migration.includes("VALIDATE CONSTRAINT expenses_tenant_expense_account_fkey"));
});
