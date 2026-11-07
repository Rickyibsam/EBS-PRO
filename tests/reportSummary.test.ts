import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const reportMigration = await readFile(
  new URL("../supabase/migrations/20261107045721_add_date_filtered_erp_report_summary.sql", import.meta.url),
  "utf8"
);
const permissionMigration = await readFile(
  new URL("../supabase/migrations/20261107045832_enforce_report_summary_custom_view_permission.sql", import.meta.url),
  "utf8"
);
const operations = await readFile(
  new URL("../src/OperationsModule.tsx", import.meta.url),
  "utf8"
);

test("ERP report RPC is date-filtered, tenant-scoped and invoker-secured", () => {
  assert.match(reportMigration, /p_tenant_id uuid/);
  assert.match(reportMigration, /p_from_date date/);
  assert.match(reportMigration, /p_to_date date/);
  assert.match(reportMigration, /SECURITY INVOKER/i);
  assert.match(reportMigration, /set search_path/i);
  assert.match(reportMigration, /revoke all on function public\.get_erp_report_summary/i);
  assert.match(reportMigration, /grant execute on function public\.get_erp_report_summary\(uuid,date,date\) to authenticated/i);
});

test("ERP report RPC enforces explicit per-user view overrides", () => {
  assert.match(permissionMigration, /module_permission_guard_internal\(p_tenant_id, 'reports_analytics', 'view'\)/);
});

test("Reports UI uses server aggregation and exposes date range plus exports", () => {
  assert.match(operations, /db\.rpc\("get_erp_report_summary"/);
  assert.match(operations, /Report from date/);
  assert.match(operations, /Report to date/);
  assert.match(operations, /Export Excel-compatible CSV/);
  assert.match(operations, /Print \/ Save PDF/);
});
