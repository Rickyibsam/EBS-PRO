import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const modules = [
  "InvoiceModule.tsx",
  "ReturnsModule.tsx",
  "BankReconciliationModule.tsx",
  "VendorReconciliationModule.tsx"
];

for (const name of modules) {
  test(name + " uses the shared UTF-8 BOM and CRLF CSV serializer", async () => {
    const source = await readFile(new URL("../src/" + name, import.meta.url), "utf8");
    assert.match(source, /import \{buildCsvWithBom\} from "\.\/lib\/csvExport"/);
    assert.ok(source.includes("buildCsvWithBom("));
    assert.ok(!source.includes('.join("\\\\r\\\\n")'), "CSV must not contain literal escaped CRLF text");
    assert.ok(!source.includes('"\\\\uFEFF"'), "CSV must not contain a literal escaped BOM prefix");
  });
}
