import test from "node:test";
import assert from "node:assert/strict";
import {findProductByBarcodeOrSku,isModuleActionAllowed,resolveAllowedNavigation} from "../src/lib/erpAccess";

const nav=["Overview","Sales","Booker App","Inventory","Purchases","Accounts","Distribution","Team & Employees","Reports","User Permissions"];
const groups=[
 {items:["Overview"]},{items:["Sales"]},{items:["Booker App"]},{items:["Inventory"]},
 {items:["Purchases"]},{items:["Accounts"]},{items:["Distribution"]},{items:["Team & Employees"]},
 {items:["Reports"]},{items:["User Permissions"]}
];
const roles:Record<string,string[]>={viewer:["Overview","Reports"],sales:["Overview","Sales"],owner:nav,admin:nav.filter(x=>x!=="User Permissions")};

test("role baseline remains in force when no custom override exists",()=>{
 assert.deepEqual(resolveAllowedNavigation("viewer",nav,roles,groups,{}),["Overview","Reports"]);
});
test("explicit module grant can extend a staff role's navigation",()=>{
 const allowed=resolveAllowedNavigation("viewer",nav,roles,groups,{sales_customer:true});
 assert.ok(allowed.includes("Sales"));
});
test("explicit module denial removes a module allowed by the role",()=>{
 const allowed=resolveAllowedNavigation("sales",nav,roles,groups,{sales_customer:false});
 assert.ok(!allowed.includes("Sales"));
 assert.ok(allowed.includes("Overview"));
});
test("owner retains full access and administrator cannot open owner-only permissions",()=>{
 assert.ok(resolveAllowedNavigation("owner",nav,roles,groups,{}).includes("User Permissions"));
 assert.ok(!resolveAllowedNavigation("admin",nav,roles,groups,{}).includes("User Permissions"));
});
test("mutating actions require view permission",()=>{
 assert.equal(isModuleActionAllowed({can_view:false,can_create:true,can_update:true,can_delete:true},"can_create"),false);
 assert.equal(isModuleActionAllowed({can_view:true,can_create:true,can_update:false,can_delete:false},"can_create"),true);
 assert.equal(isModuleActionAllowed({can_view:true,can_create:true,can_update:false,can_delete:false},"can_update"),false);
});
test("barcode lookup prefers an exact barcode match",()=>{
 const products=[{sku:"SKU-1",barcode:"1234567890123",name:"First"},{sku:"1234567890123",barcode:"999",name:"Second"}];
 assert.equal(findProductByBarcodeOrSku(" 1234567890123 ",products)?.name,"First");
});
test("barcode lookup supports case-insensitive SKU scans and ignores blank input",()=>{
 const products=[{sku:"sku-blue-01",barcode:null},{sku:"SKU-RED-02",barcode:""}];
 assert.equal(findProductByBarcodeOrSku(" SKU-BLUE-01 ",products)?.sku,"sku-blue-01");
 assert.equal(findProductByBarcodeOrSku("   ",products),undefined);
 assert.equal(findProductByBarcodeOrSku("not-found",products),undefined);
});
