import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261106120000_harden_booker_offline_idempotency.sql", import.meta.url),
  "utf8"
);

test("Booker order replay is checked before mutable route and price configuration", () => {
  const replay = migration.indexOf("Replay a committed request");
  const route = migration.indexOf("public.route_assignments");
  const priceList = migration.indexOf("public.customer_price_lists");
  assert.ok(replay >= 0 && route > replay && priceList > replay);
  assert.match(migration, /so\.created_by = v_user_id/);
  assert.match(migration, /so\.order_source = 'order_booker'/);
});

test("concurrent Booker request conflicts never return another user's order ID", () => {
  assert.match(migration, /ON CONFLICT \(tenant_id, client_request_id\)/);
  assert.match(migration, /IF v_order_id IS NULL THEN\s+RAISE EXCEPTION 'Client request ID is already in use'/);
});

test("server remains authoritative for customer price, unit conversion and tax", () => {
  assert.match(migration, /pp\.price_list_id = v_price_list_id/);
  assert.match(migration, /pu\.conversion_to_base/);
  assert.match(migration, /p\.sales_tax_rate/);
  assert.match(migration, /v_tax_total := v_tax_total \+ round\(v_line_total \* COALESCE\(v_tax_rate,0\) \/ 100, 2\)/);
});
