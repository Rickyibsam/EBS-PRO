import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const audit = await readFile(
  new URL("../supabase/tests/erp_readonly_integrity_audit.sql", import.meta.url),
  "utf8"
);

test("read-only production audit covers RLS and validated constraints", () => {
  assert.ok(audit.includes("tables_without_rls"));
  assert.ok(audit.includes("unvalidated_constraints"));
  assert.ok(audit.includes("contype in ('f','c')"));
});

test("read-only production audit reconciles posted accounting and payroll", () => {
  assert.ok(audit.includes("posted_journal_unbalanced"));
  assert.ok(audit.includes("posted_sales_invoice_total_mismatch"));
  assert.ok(audit.includes("posted_purchase_invoice_total_mismatch"));
  assert.ok(audit.includes("posted_payroll_without_journal"));
  assert.ok(audit.includes("paid_payroll_without_journal"));
});

test("tenant isolation audit checks cross-tenant references, composite FKs and indexes", () => {
  assert.ok(audit.includes("cross_tenant_reference_rows"));
  assert.ok(audit.includes("tenant_fk_without_composite_pair"));
  assert.ok(audit.includes("tenant_fk_missing_child_indexes"));
  assert.ok(audit.includes("c.tenant_id is distinct from p.tenant_id"));
  assert.ok(audit.includes("unnest(r.conkey,r.confkey)"));
});

test("security audit checks SECURITY DEFINER search_path and voucher RPC guards", () => {
  assert.ok(audit.includes("security_definer_without_search_path"));
  assert.ok(audit.includes("updated_at_trigger_missing_column"));
  assert.ok(audit.includes("backup_restore_invalid_jsonb_object_length"));
  assert.ok(audit.includes("voucher_rpc_custom_permission_guards"));
  assert.ok(audit.includes("module_permission_guard_internal"));
});

test("production audit limits writes to its transaction-scoped findings table", () => {
  const normalized = audit.toLowerCase();
  assert.ok(normalized.includes("create temporary table"));
  assert.ok(!normalized.includes("insert into public."));
  assert.ok(!normalized.includes("update public."));
  assert.ok(!normalized.includes("delete from public."));
  assert.ok(!normalized.includes("drop table public."));
  assert.ok(!normalized.includes("alter table public."));
});
