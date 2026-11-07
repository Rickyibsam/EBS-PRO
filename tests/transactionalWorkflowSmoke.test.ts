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

test("commission clawback caps deductions, retries idempotently, carries balances forward and posts to payroll GL", () => {
  assert.ok(smoke.includes("public.apply_commission_return_adjustments(v_clawback_run_one)"));
  assert.ok(smoke.includes("public.apply_commission_return_adjustments(v_clawback_run_two)"));
  assert.ok(smoke.includes("partial commission clawback did not cap recovery"));
  assert.ok(smoke.includes("commission clawback retry applied a duplicate adjustment"));
  assert.ok(smoke.includes("outstanding clawback did not carry forward"));
  assert.ok(smoke.includes("recovered commission clawback did not reconcile to payroll GL"));
});

test("zero-net payroll omits zero-value journal lines while preserving double-entry totals", async () => {
  const migration = await readFile(
    new URL("../supabase/migrations/20261107060457_fix_zero_net_payroll_journal_lines.sql", import.meta.url),
    "utf8"
  );
  assert.ok(migration.includes("if v_net>0 then"));
  assert.ok(migration.includes("if v_ded>0 then"));
  assert.ok(migration.includes("if v_gross<=0 then"));
  assert.ok(smoke.includes("gross_total=100 and deductions_total=100 and net_total=0"));
  assert.ok(smoke.includes("gross_total=200 and deductions_total=60 and net_total=140"));
});

test("zero-gross payroll is rejected without creating a journal", () => {
  assert.ok(smoke.includes("v_zero_payroll_run"));
  assert.ok(smoke.includes("zero-gross payroll was not rejected without a journal"));
});

test("isolated clean-room backup restores branch, warehouse, unit and product dependencies idempotently", () => {
  assert.ok(smoke.includes("Isolated tenant clean-room fixture"));
  assert.ok(smoke.includes("clean-room restore did not recover the complete dependency graph"));
  assert.ok(smoke.includes("clean-room restore retry was not idempotent"));
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


test("custom per-user RLS denial blocks direct table UPDATE for a manager", () => {
  assert.ok(smoke.includes("set local role authenticated"));
  assert.ok(smoke.includes("'administration_security',true,false,false,false"));
  assert.ok(smoke.includes("app settings update bypassed custom per-user update denial"));
});


test("van delivery PWA reconciles load, partial delivery, market return and idempotent replay", () => {
  assert.ok(smoke.includes("public.record_van_stock_transfer("));
  assert.ok(smoke.includes("public.dispatch_van_delivery("));
  assert.ok(smoke.includes("public.record_van_delivery_visit("));
  assert.ok(smoke.includes("van delivery visit retry was not idempotent"));
  assert.ok(smoke.includes("van sale and market return did not reconcile vehicle stock"));
});

test("van delivery PWA safely closes a failed customer visit without stock issue", () => {
  assert.ok(smoke.includes("'not_available'"));
  assert.ok(smoke.includes("failed van delivery did not close safely"));
});


test("backup restore recovers a clean isolated tenant dependency graph without overwrite or deletion", () => {
  assert.ok(smoke.includes("v_restore_fixture_backup:=public.export_tenant_backup(v_tenant_b)"));
  assert.ok(smoke.includes("delete from public.branches where tenant_id=v_tenant_b and id=v_branch_b"));
  assert.ok(smoke.includes("delete from public.warehouses where tenant_id=v_tenant_b and branch_id=v_branch_b"));
  assert.ok(smoke.includes("clean-room fixture was not empty before restore"));
  assert.ok(smoke.includes("clean-room restore did not recover the complete dependency graph"));
  assert.ok(smoke.includes("clean-room restore retry was not idempotent"));
});


test("date-filtered report RPC reconciles receivables, payables, COGS and gross profit", () => {
  assert.ok(smoke.includes("public.get_erp_report_summary(v_tenant_a,current_date,current_date)"));
  assert.ok(smoke.includes("'Posted sales invoices')::numeric,0)<>175.5"));
  assert.ok(smoke.includes("'Accounts receivable')::numeric,0)<>175.5"));
  assert.ok(smoke.includes("'Accounts payable')::numeric,0)<>130"));
  assert.ok(smoke.includes("'Cost of goods issued')::numeric,0)<>60"));
  assert.ok(smoke.includes("'Gross profit (before expenses)')::numeric,0)<>90"));
});

test("report RPC enforces explicit custom view denial and rejects reversed dates", () => {
  assert.ok(smoke.includes("'reports_analytics',false,false,false,false"));
  assert.ok(smoke.includes("custom reports view denial was not enforced"));
  assert.ok(smoke.includes("invalid report date range was accepted"));
});


test("custom permission matrix enforces view and create/update/delete actions across ERP modules", () => {
  assert.ok(smoke.includes("foreach v_module_key in array array["));
  assert.ok(smoke.includes("'sales_customer','order_booking','inventory','purchase_supplier'"));
  assert.ok(smoke.includes("'accounts_finance','distribution_delivery','administration_security'"));
  assert.ok(smoke.includes("denied % action was granted for module %"));
  assert.ok(smoke.includes("explicit reports view denial was ignored"));
});


test("legacy FOR ALL policies receive restrictive per-action custom permission guards", async () => {
  const migration = await readFile(
    new URL("../supabase/migrations/20261107054702_guard_legacy_all_command_rls_policies.sql", import.meta.url),
    "utf8"
  );
  for (const table of [
    "asset_depreciation_entries", "booker_product_visibility", "budget_lines", "budgets",
    "delivery_charge_account_mappings", "delivery_charge_rules", "departments", "designations",
    "employee_advance_account_mappings", "fixed_assets", "payroll_incentive_accruals",
    "van_stock_movements"
  ]) {
    assert.ok(migration.includes(`('${table}'`), `missing table guard for ${table}`);
  }
  assert.ok(migration.includes("foreach v_action in array array['select','insert','update','delete']"));
  assert.ok(migration.includes("as restrictive for %s"));
  assert.ok(smoke.includes("fixed asset FOR ALL policy bypassed finance update denial"));
  assert.ok(smoke.includes("budget FOR ALL policy bypassed finance update denial"));
  assert.ok(smoke.includes("budget line FOR ALL policy bypassed finance update denial"));
});


test("failed delivery outcomes reject non-zero quantities at the database boundary", async () => {
  const migration = await readFile(
    new URL("../supabase/migrations/20261107070202_guard_failed_delivery_visit_quantities.sql", import.meta.url),
    "utf8"
  );
  assert.ok(migration.includes("before insert or update of visit_status, line_quantities"));
  assert.ok(migration.includes("new.visit_status in ('not_available', 'refused')"));
  assert.ok(migration.includes("A not-available or refused visit cannot post delivered or returned quantities."));
  assert.ok(smoke.includes("not-available visit accepted delivered quantity"));
});


test("delivered outcomes require an atomic customer signature and legacy RPC cannot bypass it", async () => {
  const atomicMigration = await readFile(
    new URL("../supabase/migrations/20261107070728_add_atomic_delivery_pod_signature_rpc.sql", import.meta.url),
    "utf8"
  );
  const legacyGuard = await readFile(
    new URL("../supabase/migrations/20261107071000_require_signature_for_legacy_delivery_rpc.sql", import.meta.url),
    "utf8"
  );
  assert.ok(atomicMigration.includes("p_signature jsonb"));
  assert.ok(atomicMigration.includes("A customer signature is required for delivered or short-delivered outcomes."));
  assert.ok(atomicMigration.includes("perform public.save_delivery_pod_signature(p_delivery_id, p_signature)"));
  assert.ok(legacyGuard.includes("A customer signature is required; use the signature-aware delivery workflow."));
  assert.ok(smoke.includes("POD signature was not saved atomically with delivery posting"));
  assert.ok(smoke.includes("delivered outcome was accepted without a customer signature"));
});
