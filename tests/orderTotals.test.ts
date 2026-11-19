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

test("aggregates multiple order lines without rounding the source totals",()=>{
 const totals=calculateOrderTotals([
  {quantity:1,rate:50,tax_rate:0,discount:0},
  {quantity:2,rate:25,tax_rate:10,discount:5}
 ]);
 assert.equal(totals.subtotal,100);
 assert.equal(totals.discountTotal,5);
 assert.equal(totals.taxTotal,4.5);
 assert.equal(totals.grandTotal,99.5);
});
