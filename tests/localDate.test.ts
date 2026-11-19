import test from "node:test";
import assert from "node:assert/strict";
import {toLocalDateInput,toLocalMonthInput,toLocalMonthStart,toLocalMonthEnd} from "../src/lib/localDate";

test("formats local business dates without UTC date shifting",()=>{
 const date=new Date(2026,10,19,0,15,0);
 assert.equal(toLocalDateInput(date),"2026-11-19");
 assert.equal(toLocalMonthInput(date),"2026-11");
 assert.equal(toLocalMonthStart(date),"2026-11-01");
 assert.equal(toLocalMonthEnd(date),"2026-11-30");
});
