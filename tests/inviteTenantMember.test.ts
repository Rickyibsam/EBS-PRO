import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("staff invitation endpoint supports the Delivery Man role without allowing Owner assignment", async () => {
  const source = await readFile(new URL("../supabase/functions/invite-tenant-member/index.ts", import.meta.url), "utf8");
  const roleList = source.match(/const allowed = \[([^\]]+)\]/);
  assert.ok(roleList, "the server-side staff role allow-list must exist");
  assert.match(roleList[1], /"delivery_man"/, "Delivery Man must be assignable");
  assert.doesNotMatch(roleList[1], /"owner"/, "Owner must never be assignable through staff invitations");
});
