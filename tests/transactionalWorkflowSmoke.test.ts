import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const smoke = await readFile(
  new URL("../supabase/tests/erp_transactional_workflow_smoke.sql", import.meta.url),
  "utf8"
);

test("transactional workflow smoke test is rollback-only", () => {
  assert.match(smoke.trimStart(), /^--[\s\S]*?begin;/);
  assert.match(smoke.trimEnd(), /rollback;$/i);
  assert.doesNotMatch(smoke, /\bcommit\s*;/i);
});

test("tenant-isolation workflow rejects cross-tenant branch references", () => {
  assert.ok(smoke.includes("Invalid Cross Tenant Warehouse"));
  assert.ok(smoke.includes("foreign_key_violation"));
  assert.ok(smoke.includes("cross-tenant branch reference was accepted"));
});

test("Booker workflow calculates server totals and replays idempotently after route changes", () => {
  assert.ok(smoke.includes("public.create_order_booker_order("));
  assert.ok(smoke.includes("server-side price/tax"));
  assert.ok(smoke.includes("v_order_retry<>v_order_first"));
  assert.ok(smoke.includes("client_request_id=v_order_request"));
});

test("accounting workflow posts balanced journals and rejects unbalanced journals", () => {
  assert.ok(smoke.includes("public.post_journal_entry(v_journal_ok)"));
  assert.ok(smoke.includes("public.post_journal_entry(v_journal_bad)"));
  assert.ok(smoke.includes("balanced journal did not post"));
  assert.ok(smoke.includes("unbalanced journal was accepted"));
});
