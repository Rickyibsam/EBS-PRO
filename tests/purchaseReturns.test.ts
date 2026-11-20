import test from "node:test";
import assert from "node:assert/strict";
import {getPurchaseReturnNoteStatus} from "../src/lib/purchaseReturns";

test("purchase return relation status supports PostgREST object cardinality", () => {
  assert.equal(getPurchaseReturnNoteStatus({status:"draft"}), "draft");
  assert.equal(getPurchaseReturnNoteStatus({status:"posted"}), "posted");
});

test("purchase return relation status remains compatible with array cardinality", () => {
  assert.equal(getPurchaseReturnNoteStatus([{status:"draft"}]), "draft");
  assert.equal(getPurchaseReturnNoteStatus([{status:"void"}]), "void");
});

test("missing or malformed purchase return relation has no active status", () => {
  assert.equal(getPurchaseReturnNoteStatus(null), null);
  assert.equal(getPurchaseReturnNoteStatus([]), null);
  assert.equal(getPurchaseReturnNoteStatus({}), null);
  assert.equal(getPurchaseReturnNoteStatus("draft"), null);
});
