export type OfflineBookerOrder = {
  id:string; kind:"order"; tenantId:string; userId:string; routeId:string; customerId:string; requestId:string;
  requiredDeliveryDate:string|null; notes:string|null;
  lines:Array<{product_id:string;unit_id:string;quantity:number}>;
  createdAt:string;
};
const DB_NAME="ebs-pro-offline";const STORE="booker-orders";const VISITS="booker-visits";const DRAFTS="booker-drafts";
function openDb():Promise<IDBDatabase>{
 return new Promise((resolve,reject)=>{const request=indexedDB.open(DB_NAME,3);request.onupgradeneeded=()=>{const db=request.result;if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:"id"});if(!db.objectStoreNames.contains(VISITS))db.createObjectStore(VISITS,{keyPath:"id"});if(!db.objectStoreNames.contains(DRAFTS))db.createObjectStore(DRAFTS,{keyPath:"id"});};request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error||new Error("Offline storage could not be opened."));});
}
export async function enqueueBookerOrder(order:OfflineBookerOrder):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(STORE,"readwrite");tx.objectStore(STORE).put(order);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Offline order could not be saved."));tx.onabort=()=>reject(tx.error||new Error("Offline order save was cancelled."));});db.close();
}
export async function getPendingBookerOrders(tenantId:string,userId:string):Promise<OfflineBookerOrder[]>{
 const db=await openDb();const rows=await new Promise<OfflineBookerOrder[]>((resolve,reject)=>{const tx=db.transaction(STORE,"readonly");const request=tx.objectStore(STORE).getAll();request.onsuccess=()=>resolve((request.result as OfflineBookerOrder[]).filter(x=>x.kind==="order"&&x.tenantId===tenantId&&x.userId===userId).sort((a,b)=>a.createdAt.localeCompare(b.createdAt)));request.onerror=()=>reject(request.error||new Error("Offline orders could not be read."));});db.close();return rows;
}
export async function removePendingBookerOrder(id:string):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(STORE,"readwrite");tx.objectStore(STORE).delete(id);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Synced order could not be removed from offline queue."));});db.close();
}

export type BookerOfflineSnapshot = {id:string;kind:"snapshot";tenantId:string;userId:string;data:Record<string,unknown>;updatedAt:string};
export async function cacheBookerSnapshot(tenantId:string,userId:string,patch:Record<string,unknown>):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{
  const tx=db.transaction(STORE,"readwrite"),store=tx.objectStore(STORE),key="snapshot-"+tenantId+"-"+userId;
  const request=store.get(key);request.onsuccess=()=>{const old=request.result as BookerOfflineSnapshot|undefined;store.put({id:key,kind:"snapshot",tenantId,userId,data:{...(old?.data||{}),...patch},updatedAt:new Date().toISOString()});};
  request.onerror=()=>reject(request.error||new Error("Offline Booker snapshot could not be read."));
  tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Offline Booker snapshot could not be saved."));
 });db.close();
}
export async function getBookerSnapshot(tenantId:string,userId:string):Promise<BookerOfflineSnapshot|null>{
 const db=await openDb();const value=await new Promise<BookerOfflineSnapshot|null>((resolve,reject)=>{const tx=db.transaction(STORE,"readonly"),request=tx.objectStore(STORE).get("snapshot-"+tenantId+"-"+userId);request.onsuccess=()=>resolve((request.result as BookerOfflineSnapshot)||null);request.onerror=()=>reject(request.error||new Error("Offline Booker snapshot could not be loaded."));});db.close();return value;
}

export type OfflineBookerVisit={id:string;kind:"visit";tenantId:string;userId:string;routeId:string;customerId:string;requestId:string;visitAt:string;latitude:number|null;longitude:number|null;notes:string|null;createdAt:string};
export async function enqueueBookerVisit(visit:OfflineBookerVisit):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(VISITS,"readwrite");tx.objectStore(VISITS).put(visit);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Offline Booker visit could not be queued."));tx.onabort=()=>reject(tx.error||new Error("Offline Booker visit queue was cancelled."));});db.close();
}
export async function getPendingBookerVisits(tenantId:string,userId:string):Promise<OfflineBookerVisit[]>{
 const db=await openDb();const rows=await new Promise<OfflineBookerVisit[]>((resolve,reject)=>{const tx=db.transaction(VISITS,"readonly");const req=tx.objectStore(VISITS).getAll();req.onsuccess=()=>resolve((req.result as OfflineBookerVisit[]).filter(x=>x.tenantId===tenantId&&x.userId===userId).sort((a,b)=>a.createdAt.localeCompare(b.createdAt)));req.onerror=()=>reject(req.error||new Error("Queued Booker visits could not be read."));});db.close();return rows;
}
export async function removePendingBookerVisit(id:string):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(VISITS,"readwrite");tx.objectStore(VISITS).delete(id);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Synced Booker visit could not be removed."));});db.close();
}

export type BookerOfflineDraft = {
 id:string;kind:"draft";tenantId:string;userId:string;
 data:Record<string,unknown>;updatedAt:string;
};
export async function saveBookerDraft(tenantId:string,userId:string,data:Record<string,unknown>):Promise<void>{
 if(!tenantId||!userId)return;
 const db=await openDb();
 await new Promise<void>((resolve,reject)=>{
  const tx=db.transaction(DRAFTS,"readwrite");
  tx.objectStore(DRAFTS).put({id:"draft-"+tenantId+"-"+userId,kind:"draft",tenantId,userId,data,updatedAt:new Date().toISOString()});
  tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Offline Booker draft could not be saved."));
  tx.onabort=()=>reject(tx.error||new Error("Offline Booker draft save was cancelled."));
 });
 db.close();
}
export async function getBookerDraft(tenantId:string,userId:string):Promise<BookerOfflineDraft|null>{
 if(!tenantId||!userId)return null;
 const db=await openDb();
 const value=await new Promise<BookerOfflineDraft|null>((resolve,reject)=>{
  const tx=db.transaction(DRAFTS,"readonly");
  const request=tx.objectStore(DRAFTS).get("draft-"+tenantId+"-"+userId);
  request.onsuccess=()=>resolve((request.result as BookerOfflineDraft)||null);
  request.onerror=()=>reject(request.error||new Error("Offline Booker draft could not be loaded."));
 });
 db.close();return value;
}
export async function clearBookerOfflineUserData(tenantId:string,userId:string):Promise<void>{
 if(!tenantId||!userId)return;
 const db=await openDb();
 await new Promise<void>((resolve,reject)=>{
  // Keep queued orders and visits: deleting an unsynchronized transaction on logout
  // would cause business-data loss. Clear only cached catalogue/customer snapshots and drafts.
  const tx=db.transaction([STORE,DRAFTS],"readwrite");
  const snapshotStore=tx.objectStore(STORE),snapshotRequest=snapshotStore.getAll();
  snapshotRequest.onsuccess=()=>{
   for(const row of snapshotRequest.result as Array<{id:string;kind?:string;tenantId?:string;userId?:string}>){
    if(row.kind==="snapshot"&&row.tenantId===tenantId&&row.userId===userId)snapshotStore.delete(row.id);
   }
  };
  snapshotRequest.onerror=()=>{try{tx.abort();}catch{}};
  const draftStore=tx.objectStore(DRAFTS),draftRequest=draftStore.getAll();
  draftRequest.onsuccess=()=>{
   for(const row of draftRequest.result as Array<{id:string;tenantId?:string;userId?:string}>){
    if(row.tenantId===tenantId&&row.userId===userId)draftStore.delete(row.id);
   }
  };
  draftRequest.onerror=()=>{try{tx.abort();}catch{}};
  tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Offline Booker cache could not be cleared."));
  tx.onabort=()=>reject(tx.error||new Error("Offline Booker cache cleanup was cancelled."));
 });
 db.close();
}
