import "fake-indexeddb/auto";
import test from "node:test";
import assert from "node:assert/strict";
import {
 enqueueBookerOrder,getPendingBookerOrders,removePendingBookerOrder,
 cacheBookerSnapshot,getBookerSnapshot,enqueueBookerVisit,getPendingBookerVisits,removePendingBookerVisit
} from "../src/bookerOfflineQueue";
import {
 queueDeliveryVisit,getQueuedDeliveryVisits,removeQueuedDeliveryVisit,
 cacheDeliverySnapshot,getDeliverySnapshot
} from "../src/deliveryOfflineQueue";

test("Booker offline orders are isolated by tenant and user, ordered, and removable",async()=>{
 const tenant="tenant-booker-test",user="user-booker-test";
 const base={kind:"order" as const,tenantId:tenant,userId:user,routeId:"route",customerId:"customer",requestId:"request",requiredDeliveryDate:null,notes:null,lines:[{product_id:"p",unit_id:"u",quantity:2}]};
 await enqueueBookerOrder({...base,id:"later",createdAt:"2026-01-02T00:00:00.000Z"});
 await enqueueBookerOrder({...base,id:"earlier",createdAt:"2026-01-01T00:00:00.000Z"});
 await enqueueBookerOrder({...base,id:"other-user",userId:"another-user",createdAt:"2026-01-01T00:00:00.000Z"});
 const queued=await getPendingBookerOrders(tenant,user);
 assert.deepEqual(queued.map(x=>x.id),["earlier","later"]);
 await removePendingBookerOrder("earlier");
 assert.deepEqual((await getPendingBookerOrders(tenant,user)).map(x=>x.id),["later"]);
});
test("Booker offline snapshot patches merge without crossing user scope",async()=>{
 const tenant="tenant-booker-snapshot",user="user-booker-snapshot";
 await cacheBookerSnapshot(tenant,user,{customers:[{id:"c1"}],routeId:"r1"});
 await cacheBookerSnapshot(tenant,user,{customerId:"c1",prices:[{id:"price1"}]});
 const snapshot=await getBookerSnapshot(tenant,user);
 assert.deepEqual(snapshot?.data,{customers:[{id:"c1"}],routeId:"r1",customerId:"c1",prices:[{id:"price1"}]});
 assert.equal(await getBookerSnapshot(tenant,"other-user"),null);
});
test("Booker GPS visits stay queued until explicit successful-sync removal",async()=>{
 const tenant="tenant-booker-visits",user="user-booker-visits";
 const visit={id:"visit-1",kind:"visit" as const,tenantId:tenant,userId:user,routeId:"route",customerId:"customer",requestId:"idem-1",visitAt:"2026-01-01T00:00:00.000Z",latitude:null,longitude:null,notes:"offline",createdAt:"2026-01-01T00:00:00.000Z"};
 await enqueueBookerVisit(visit);
 assert.equal((await getPendingBookerVisits(tenant,user)).length,1);
 await removePendingBookerVisit(visit.id);
 assert.equal((await getPendingBookerVisits(tenant,user)).length,0);
});
test("Deliveryman offline visits are tenant/user scoped and removable after sync",async()=>{
 const tenant="tenant-delivery-test",user="user-delivery-test";
 const visit={id:"delivery-visit-1",idempotency_key:"idem-delivery-1",vehicle_number:"ABC-123",user_id:user,tenant_id:tenant,delivery_id:"delivery",delivery_man_employee_id:"employee",customer_id:"customer",visit_status:"delivered",shops_visited:1,line_quantities:[],notes:null,created_by:user,queued_at:"2026-01-01T00:00:00.000Z"};
 await queueDeliveryVisit(visit);
 assert.equal((await getQueuedDeliveryVisits(tenant,user)).length,1);
 assert.equal((await getQueuedDeliveryVisits(tenant,"another-user")).length,0);
 await removeQueuedDeliveryVisit(visit.id);
 assert.equal((await getQueuedDeliveryVisits(tenant,user)).length,0);
});
test("Deliveryman offline snapshot is saved and restored for its owner",async()=>{
 const tenant="tenant-delivery-snapshot",user="user-delivery-snapshot";
 await cacheDeliverySnapshot(tenant,user,{deliveries:[{id:"d1"}],route:"north"});
 const snapshot=await getDeliverySnapshot(tenant,user);
 assert.deepEqual(snapshot?.data,{deliveries:[{id:"d1"}],route:"north"});
 assert.equal(await getDeliverySnapshot(tenant,"another-user"),null);
});
