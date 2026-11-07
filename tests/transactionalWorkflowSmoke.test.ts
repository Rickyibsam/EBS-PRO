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

test("database voucher RPC rejects direct updates denied by custom permissions", () => {
  assert.ok(smoke.includes("tenant_user_module_permissions"));
  assert.ok(smoke.includes("public.update_draft_voucher_lines("));
  assert.ok(smoke.includes("direct voucher RPC bypassed custom update denial"));
});

test("purchase workflow posts GRN stock, supplier invoice, and purchase return", () => {
  assert.ok(smoke.includes("public.post_goods_receipt(v_grn)"));
  assert.ok(smoke.includes("public.create_purchase_invoice("));
  assert.ok(smoke.includes("public.post_purchase_invoice(v_purchase_invoice)"));
  assert.ok(smoke.includes("public.create_purchase_debit_note("));
  assert.ok(smoke.includes("public.post_purchase_debit_note(v_debit_note)"));
  assert.ok(smoke.includes("purchase_return"));
});

test("sales workflow dispatches stock and creates a posted invoice", () => {
  assert.ok(smoke.includes("public.create_delivery_for_approved_order("));
  assert.ok(smoke.includes("public.dispatch_delivery("));
  assert.ok(smoke.includes("public.complete_delivery("));
  assert.ok(smoke.includes("sales invoice did not create an AR/revenue journal"));
});

test("payroll workflow posts accrual, pays once, and rejects invalid calculations", () => {
  assert.ok(smoke.includes("public.post_payroll_run(v_payroll_run)"));
  assert.ok(smoke.includes("public.pay_payroll_line(v_payroll_line"));
  assert.ok(smoke.includes("already_paid"));
  assert.ok(smoke.includes("invalid payroll arithmetic was not safely rejected"));
});

test("fixed asset workflow posts depreciation once and disposes with a balanced GL journal", () => {
  assert.ok(smoke.includes("public.post_asset_monthly_depreciation("));
  assert.ok(smoke.includes("v_depreciation_retry"));
  assert.ok(smoke.includes("public.dispose_fixed_asset("));
  assert.ok(smoke.includes("asset disposal did not post its GL journal"));
});

test("budget actuals report supported company and source-inferred branch scope", () => {
  assert.ok(smoke.includes("public.get_budget_actuals(v_tenant_a)"));
  assert.ok(smoke.includes("company-wide budget actuals were not supported"));
  assert.ok(smoke.includes("source-inferred branch attribution"));
});

test("backup export and same-tenant additive restore are complete and idempotent", () => {
  assert.ok(smoke.includes("public.export_tenant_backup(v_tenant_a)"));
  assert.ok(smoke.includes("public.restore_tenant_backup(v_tenant_a,v_backup)"));
  assert.ok(smoke.includes("additive_only_no_overwrite_no_delete"));
});

test("accounting workflow posts balanced journals and rejects unbalanced journals", () => {
  assert.ok(smoke.includes("public.post_journal_entry(v_journal_ok)"));
  assert.ok(smoke.includes("public.post_journal_entry(v_journal_bad)"));
  assert.ok(smoke.includes("balanced journal did not post"));
  assert.ok(smoke.includes("unbalanced journal was accepted"));
});


test("inventory workflow transfers stock and posts physical stock-count variances", () => {
  assert.ok(smoke.includes("public.post_stock_transfer(v_stock_transfer)"));
  assert.ok(smoke.includes("public.create_stock_take("));
  assert.ok(smoke.includes("public.post_stock_take(v_stock_take)"));
  assert.ok(smoke.includes("physical stock count did not create the variance movement"));
});

test("delivery workflow persists POD signature after delivery outcome", () => {
  assert.ok(smoke.includes("public.save_delivery_pod_signature("));
  assert.ok(smoke.includes("delivery POD signature was not persisted"));
});

test("HR workflow records attendance and approves leave", () => {
  assert.ok(smoke.includes("public.record_employee_attendance("));
  assert.ok(smoke.includes("public.decide_employee_leave("));
  assert.ok(smoke.includes("employee leave approval was not recorded"));
});
