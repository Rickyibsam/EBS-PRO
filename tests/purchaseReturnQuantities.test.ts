import test from "node:test";
import assert from "node:assert/strict";
import {sumActivePurchaseReturnQuantities} from "../src/lib/purchaseReturnQuantities";

test("counts draft and posted returns when PostgREST returns a to-one object",()=>{
 const totals=sumActivePurchaseReturnQuantities([
  {goods_receipt_line_id:"grl-1",quantity:"2.5",purchase_debit_notes:{status:"draft"}},
  {goods_receipt_line_id:"grl-1",quantity:1,purchase_debit_notes:{status:"posted"}},
  {goods_receipt_line_id:"grl-1",quantity:9,purchase_debit_notes:{status:"void"}}
 ]);
 assert.equal(totals.get("grl-1"),3.5);
});

test("supports array-shaped relationships and ignores invalid quantities",()=>{
 const totals=sumActivePurchaseReturnQuantities([
  {goods_receipt_line_id:"grl-2",quantity:3,purchase_debit_notes:[{status:"posted"}]},
  {goods_receipt_line_id:"grl-2",quantity:"bad",purchase_debit_notes:{status:"draft"}},
  {goods_receipt_line_id:"grl-2",quantity:-1,purchase_debit_notes:{status:"draft"}},
  {goods_receipt_line_id:"grl-2",quantity:4,purchase_debit_notes:null}
 ]);
 assert.equal(totals.get("grl-2"),3);
});
