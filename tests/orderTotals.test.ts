import test from "node:test";
import assert from "node:assert/strict";
import {calculateOrderTotals} from "../src/lib/orderTotals";

test("calculates sales tax on the amount after line discount",()=>{
 const totals=calculateOrderTotals([{quantity:"2",rate:"100",tax_rate:"17",discount:"20"}]);
 assert.equal(totals.subtotal,200);
 assert.equal(totals.discountTotal,20);
 assert.equal(totals.taxTotal,30.6);
 assert.equal(totals.grandTotal,210.6);
});

test("does not allow a line discount above gross value",()=>{
 assert.throws(()=>calculateOrderTotals([{quantity:1,rate:100,tax_rate:17,discount:101}]),/discount cannot exceed/);
});
