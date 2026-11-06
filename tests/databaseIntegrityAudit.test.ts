import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const audit = await readFile(
  new URL("../supabase/tests/erp_readonly_integrity_audit.sql", import.meta.url),
  "utf8"
);

test("read-only production audit covers RLS and validated constraints", () => {
  assert.match(audit, /tables_without_rls/);
  assert.match(audit, /unvalidated_constraints/);
  assert.match(audit, /contype in \\('f','c'\\)/);
});

test("read-only production audit reconciles posted accounting and payroll", () => {
  assert.match(audit, /posted_journal_unbalanced/);
  assert.match(audit, /posted_sales_invoice_total_mismatch/);
  assert.match(audit, /posted_purchase_invoice_total_mismatch/);
  assert.match(audit, /posted_payroll_without_journal/);
  assert.match(audit, /paid_payroll_without_journal/);
});

test("tenant isolation audit checks cross-tenant references, composite FKs and indexes", () => {
  assert.match(audit, /cross_tenant_reference_rows/);
  assert.match(audit, /tenant_fk_without_composite_pair/);
  assert.match(audit, /tenant_fk_missing_child_indexes/);
  assert.match(audit, /c\\.tenant_id is distinct from p\\.tenant_id/);
  assert.match(audit, /unnest\\(r\\.conkey,r\\.confkey\\)/);
});

test("security audit checks SECURITY DEFINER search_path and voucher RPC guards", () => {
  assert.match(audit, /security_definer_without_search_path/);
  assert.match(audit, /voucher_rpc_custom_permission_guards/);
  assert.match(audit, /module_permission_guard_internal/);
});

test("production audit limits writes to its transaction-scoped findings table", () => {
  assert.match(audit, /create temporary table/i);
  assert.doesNotMatch(
    audit,
    /\\b(insert\\s+into\\s+(?!_ebs_integrity_findings)|update\\s+(?!_ebs_integrity_findings)|delete\\s+from\\s+(?!_ebs_integrity_findings)|drop\\s+table|alter\\s+table)\\b/i
  );
});
