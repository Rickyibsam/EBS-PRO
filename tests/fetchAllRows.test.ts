import assert from "node:assert/strict";
import test from "node:test";
import { fetchAllRows } from "../src/lib/fetchAllRows";

test("fetchAllRows returns a single short page", async () => {
  const rows = await fetchAllRows(async () => ({ data: [1, 2, 3], error: null }), 5);
  assert.deepEqual(rows, [1, 2, 3]);
});

test("fetchAllRows requests stable contiguous pages until the final short page", async () => {
  const source = Array.from({ length: 1_203 }, (_, index) => index + 1);
  const ranges: Array<[number, number]> = [];
  const rows = await fetchAllRows(async (from, to) => {
    ranges.push([from, to]);
    return { data: source.slice(from, to + 1), error: null };
  }, 500);

  assert.equal(rows.length, 1_203);
  assert.deepEqual(rows, source);
  assert.deepEqual(ranges, [[0, 499], [500, 999], [1000, 1499]]);
});

test("fetchAllRows propagates database page errors", async () => {
  const failure = new Error("database unavailable");
  await assert.rejects(
    () => fetchAllRows<number>(async () => ({ data: null, error: failure }), 10),
    failure
  );
});

test("fetchAllRows rejects invalid page sizes", async () => {
  await assert.rejects(() => fetchAllRows<number>(async () => ({ data: [], error: null }), 0), /positive safe integer/);
});


test("fetchAllRowsResult returns every page in a data/error result", async () => {
  const source = Array.from({ length: 1_201 }, (_, index) => index + 1);
  const result = await (await import("../src/lib/fetchAllRows")).fetchAllRowsResult<number>(
    async (from, to) => ({ data: source.slice(from, to + 1), error: null }),
    500
  );
  assert.equal(result.error, null);
  assert.deepEqual(result.data, source);
});

test("fetchAllRowsResult returns page errors without rejecting the caller", async () => {
  const failure = new Error("database unavailable");
  const result = await (await import("../src/lib/fetchAllRows")).fetchAllRowsResult<number>(
    async () => ({ data: null, error: failure }),
    10
  );
  assert.equal(result.data, null);
  assert.equal(result.error, failure);
});
