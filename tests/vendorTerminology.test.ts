import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const files = [
  "App.tsx",
  "DashboardModule.tsx",
  "UserPermissionsModule.tsx",
  "PurchaseReturnsModule.tsx",
  "PurchaseInvoiceModule.tsx",
  "TransactionsModule.tsx",
  "OperationsModule.tsx",
  "AccountingModule.tsx"
];

const legacyLabels = [
  "Purchase & Supplier Management",
  "Supplier accounts, purchasing",
  "posted supplier invoices",
  "Active supplier accounts",
  "supplier ledger",
  "New supplier return",
  "supplier payable accounting",
  "supplier invoice first",
  "<th>Supplier</th>",
  "Select a customer or supplier",
  "Loading supplier returns",
  "No supplier returns recorded.",
  "supplier bills",
  "supplier's invoice number",
  "Match a supplier invoice",
  "Loading supplier invoices",
  "No supplier invoices have been matched yet.",
  "Please select a supplier.",
  'purchase?"supplier":"customer"',
  "Purchases by supplier",
  "No posted supplier invoices recorded.",
  "individual customer and supplier accounts"
];

test("user-facing purchase screens use Vendor terminology", async () => {
  const sources = await Promise.all(files.map(name =>
    readFile(new URL("../src/" + name, import.meta.url), "utf8")
  ));
  const combined = sources.join("\n");
  for (const label of legacyLabels) {
    assert.ok(!combined.includes(label), "Legacy user-facing label remains: " + label);
  }
});
