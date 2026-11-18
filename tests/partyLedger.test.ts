import test from "node:test";
import assert from "node:assert/strict";
import {buildPartyLedgerRows} from "../src/lib/partyLedger";

test("customer ledger starts with debit opening balance",()=>{
 const rows=buildPartyLedgerRows([{party_id:"c1",account_code:"1100",entry_date:"2026-02-01",journal_number:"JV-1",debit:250,credit:0}], [{id:"c1",party_type:"customer",opening_balance:10000}], "customer", "c1");
 assert.equal(rows.length,2);assert.equal(rows[0].is_opening_balance,true);assert.equal(rows[0].debit,10000);assert.equal(rows[0].credit,0);
 assert.equal(rows.reduce((n,x)=>n+Number(x.debit)-Number(x.credit),0),10250);
});

test("vendor ledger starts with credit opening balance",()=>{
 const rows=buildPartyLedgerRows([{party_id:"v1",account_code:"2000",entry_date:"2026-02-01",journal_number:"JV-2",debit:0,credit:500}], [{id:"v1",party_type:"supplier",opening_balance:10000}], "supplier", "v1");
 assert.equal(rows[0].credit,10000);assert.equal(rows[0].debit,0);
 assert.equal(rows.reduce((n,x)=>n+Number(x.credit)-Number(x.debit),0),10500);
});

test("opening balance direction handles debit balances on vendor and credit balances on customer",()=>{
 const vendor=buildPartyLedgerRows([], [{id:"v1",party_type:"supplier",opening_balance:-400}], "supplier");
 const customer=buildPartyLedgerRows([], [{id:"c1",party_type:"customer",opening_balance:-300}], "customer");
 assert.equal(vendor[0].debit,400);assert.equal(vendor[0].credit,0);
 assert.equal(customer[0].credit,300);assert.equal(customer[0].debit,0);
});

test("all-party ledger includes opening balances only for matching party types",()=>{
 const rows=buildPartyLedgerRows([], [{id:"c1",party_type:"customer",opening_balance:100},{id:"v1",party_type:"supplier",opening_balance:200},{id:"b1",party_type:"both",opening_balance:50}], "customer");
 assert.deepEqual(rows.map(x=>x.party_id),["c1","b1"]);
});
