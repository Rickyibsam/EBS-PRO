import assert from "node:assert/strict";
import test from "node:test";
import { buildCsvWithBom } from "../src/lib/csvExport";

test("buildCsvWithBom writes a UTF-8 BOM and CRLF-delimited rows", () => {
  const csv = buildCsvWithBom([{ name: "Tea", note: 'Large, "premium"' }, { name: "Milk", note: null }], ["name", "note"]);
  assert.equal(csv, '\uFEFF"name","note"\r\n"Tea","Large, ""premium"""\r\n"Milk",""');
});

test("buildCsvWithBom safely emits an empty register header", () => {
  assert.equal(buildCsvWithBom([], ["employee", "net"]), '\uFEFF"employee","net"');
});
