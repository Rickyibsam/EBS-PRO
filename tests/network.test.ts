import test from "node:test";
import assert from "node:assert/strict";
import {isTransientNetworkError} from "../src/lib/network";

test("transient fetch and connectivity failures are queued for retry", () => {
  for (const message of [
    "Failed to fetch",
    "Network request failed",
    "Connection interrupted",
    "Request timed out",
    "Load failed",
    "NetworkError when attempting to fetch resource"
  ]) {
    assert.equal(isTransientNetworkError(new Error(message)), true, message);
  }
});

test("business validation and authorization errors are not treated as offline", () => {
  for (const message of [
    "Insufficient van stock",
    "You are not allowed to create orders",
    "Customer price list is not configured",
    "Invalid delivered quantity"
  ]) {
    assert.equal(isTransientNetworkError(new Error(message)), false, message);
  }
});
