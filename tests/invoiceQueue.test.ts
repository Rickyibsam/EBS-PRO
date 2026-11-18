import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("invoice screen shows approved sales orders waiting for delivery and invoice", async () => {
  const source = await readFile(new URL("../src/InvoiceModule.tsx", import.meta.url), "utf8");
  assert.ok(source.includes("Sales orders awaiting invoice"));
  assert.ok(source.includes('db.from("sales_orders")'));
  assert.ok(source.includes('["approved","allocated","dispatched","delivered"]'));
  assert.ok(source.includes("filter(order=>!(i.data??[]).some(invoice=>invoice.sales_order_id===order.id))"));
  assert.ok(source.includes("Complete delivery allocation, picking, dispatch and delivery confirmation"));
  assert.ok(source.includes("Invoice generation pending"));
});
