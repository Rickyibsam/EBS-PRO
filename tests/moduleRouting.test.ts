import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

const app = await readFile(new URL("../src/App.tsx", import.meta.url), "utf8");
const workspace = await readFile(new URL("../src/WorkspaceModule.tsx", import.meta.url), "utf8");

test("every navigation item is mapped to an explicit module route", () => {
  const navBody = app.match(/const nav = \[(.*?)\];/s)?.[1];
  assert.ok(navBody, "navigation list must exist");
  const navItems = [...navBody.matchAll(/"([^"]+)"/g)].map(match => match[1]);
  const routed = new Set([...app.matchAll(/active === "([^"]+)"/g)].map(match => match[1]));
  for (const group of app.matchAll(/\[([^\]]+)\]\.includes\(active\)/g)) {
    for (const item of group[1].matchAll(/"([^"]+)"/g)) routed.add(item[1]);
  }
  routed.add("Overview");
  for (const item of navItems) assert.ok(routed.has(item), `No dedicated route found for navigation item: ${item}`);
});

test("WorkspaceModule is restricted to real master-data screens and no next-phase placeholder remains", () => {
  assert.ok(app.includes('["Products","Customers","Vendors"].includes(active)'));
  assert.ok(app.includes('active === "Delivery Man App"'));
  assert.ok(!workspace.includes("aglay development phase"));
  assert.ok(workspace.includes("WorkspaceModule handles only Products, Customers and Vendors."));
});
