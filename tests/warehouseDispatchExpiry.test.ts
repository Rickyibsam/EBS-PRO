import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(
  new URL("../supabase/migrations/20261117160000_enforce_tracked_batch_expiry_on_warehouse_dispatch.sql", import.meta.url),
  "utf8"
);

test("warehouse FEFO dispatch blocks missing metadata when product tracking is enabled", () => {
  assert.ok(migration.includes("v_product.track_expiry"));
  assert.ok(migration.includes("expiry_date is not null"));
  assert.ok(migration.includes("v_product.track_batch"));
  assert.ok(migration.includes("nullif(btrim(batch_number)"));
  assert.ok(migration.includes("expiry_date >= current_date"));
  assert.ok(migration.includes("FOR SHARE"));
});
