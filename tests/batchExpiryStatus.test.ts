import test from "node:test";
import assert from "node:assert/strict";
import { getBatchExpiryIssueLabel, getBatchExpiryStatus } from "../src/lib/batchExpiryStatus";

test("tracked expiry products flag missing expiry metadata", () => {
  const product = { track_expiry: true, track_batch: false };
  const lot = { batch_number: null, expiry_date: null };
  assert.equal(getBatchExpiryStatus(product, lot, "2026-11-17", "2027-02-15"), "missing_metadata");
  assert.equal(getBatchExpiryIssueLabel(product, lot), "EXPIRY REQUIRED");
});

test("tracked batch products flag empty or missing batch numbers", () => {
  const product = { track_batch: true, track_expiry: false };
  assert.equal(getBatchExpiryStatus(product, { batch_number: "   ", expiry_date: null }, "2026-11-17", "2027-02-15"), "missing_metadata");
  assert.equal(getBatchExpiryIssueLabel(product, { batch_number: null, expiry_date: null }), "BATCH REQUIRED");
});

test("both required metadata fields are reported together", () => {
  const product = { track_batch: true, track_expiry: true };
  const lot = { batch_number: null, expiry_date: null };
  assert.equal(getBatchExpiryIssueLabel(product, lot), "BATCH & EXPIRY REQUIRED");
});

test("untracked no-expiry stock remains a valid no-date state", () => {
  assert.equal(getBatchExpiryStatus({ track_batch: false, track_expiry: false }, { batch_number: null, expiry_date: null }, "2026-11-17", "2027-02-15"), "no_date");
});

test("expired, near-expiry and healthy lots are classified separately", () => {
  const product = { track_expiry: true };
  assert.equal(getBatchExpiryStatus(product, { expiry_date: "2026-11-16" }, "2026-11-17", "2027-02-15"), "expired");
  assert.equal(getBatchExpiryStatus(product, { expiry_date: "2027-01-01" }, "2026-11-17", "2027-02-15"), "near");
  assert.equal(getBatchExpiryStatus(product, { expiry_date: "2027-08-01" }, "2026-11-17", "2027-02-15"), "good");
});
