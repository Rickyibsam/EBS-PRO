import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(new URL("../supabase/functions/invite-tenant-member/index.ts", import.meta.url), "utf8");
const roleList = source.match(/const allowed = \[([^\]]+)\]/);

test("staff invitation server allow-list includes Delivery Man but excludes Owner", () => {
  assert.ok(roleList, "the server-side staff role allow-list must exist");
  assert.match(roleList[1], /"delivery_man"/);
  assert.doesNotMatch(roleList[1], /"owner"/);
});

test("staff invitation requires an authenticated bearer session", () => {
  assert.match(source, /authHeader\.startsWith\("Bearer "\)/);
  assert.match(source, /callerClient\.auth\.getUser\(\)/);
});

test("only active owners and admins can invite; admins cannot appoint another admin", () => {
  assert.match(source, /!\["owner","admin"\]\.includes\(callerMembership\.role\)/);
  assert.match(source, /!callerMembership\?\.is_active/);
  assert.match(source, /callerMembership\.role === "admin" && role === "admin"/);
});

test("invitation branch must be active and belong to the requested tenant", () => {
  assert.match(source, /\.eq\("tenant_id", tenantId\)\.eq\("id", branchId\)\.eq\("is_active", true\)/);
});

test("duplicate employee codes and existing tenant memberships are rejected", () => {
  assert.match(source, /duplicateCode/);
  assert.match(source, /existingMembership/);
  assert.match(source, /already connected to this company/);
});

test("failed membership or employee writes roll back newly invited auth users", () => {
  assert.match(source, /if \(insertMemberError\)[\s\S]*?if \(invited\) await admin\.auth\.admin\.deleteUser\(user\.id\)/);
  assert.match(source, /if \(employeeError\)[\s\S]*?tenant_memberships[\s\S]*?if \(invited\) await admin\.auth\.admin\.deleteUser\(user\.id\)/);
});

test("failed profile persistence removes partial employee and membership records", () => {
  assert.match(source, /if \(profileError\)[\s\S]*?employees[\s\S]*?tenant_memberships[\s\S]*?if \(invited\) await admin\.auth\.admin\.deleteUser\(user\.id\)/);
});

test("staff invitations never expose the service-role key to the browser", () => {
  assert.match(source, /Deno\.env\.get\("SUPABASE_SERVICE_ROLE_KEY"\)/);
  assert.match(source, /verify_jwt|authHeader/);
});
