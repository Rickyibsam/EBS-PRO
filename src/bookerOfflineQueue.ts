export type OfflineBookerOrder = {
  id:string; kind:"order"; tenantId:string; routeId:string; customerId:string; requestId:string;
  requiredDeliveryDate:string|null; notes:string|null;
  lines:Array<{product_id:string;unit_id:string;quantity:number}>;
  createdAt:string;
};
const DB_NAME="ebs-pro-offline";const STORE="booker-orders";
function openDb():Promise<IDBDatabase>{
 return new Promise((resolve,reject)=>{const request=indexedDB.open(DB_NAME,1);request.onupgradeneeded=()=>{const db=request.result;if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:"id"});};request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error||new Error("Offline storage could not be opened."));});
}
export async function enqueueBookerOrder(order:OfflineBookerOrder):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(STORE,"readwrite");tx.objectStore(STORE).put(order);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Offline order could not be saved."));tx.onabort=()=>reject(tx.error||new Error("Offline order save was cancelled."));});db.close();
}
export async function getPendingBookerOrders(tenantId:string):Promise<OfflineBookerOrder[]>{
 const db=await openDb();const rows=await new Promise<OfflineBookerOrder[]>((resolve,reject)=>{const tx=db.transaction(STORE,"readonly");const request=tx.objectStore(STORE).getAll();request.onsuccess=()=>resolve((request.result as OfflineBookerOrder[]).filter(x=>x.kind==="order"&&x.tenantId===tenantId).sort((a,b)=>a.createdAt.localeCompare(b.createdAt)));request.onerror=()=>reject(request.error||new Error("Offline orders could not be read."));});db.close();return rows;
}
export async function removePendingBookerOrder(id:string):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(STORE,"readwrite");tx.objectStore(STORE).delete(id);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Synced order could not be removed from offline queue."));});db.close();
}

export type BookerOfflineSnapshot = {id:string;kind:"snapshot";tenantId:string;data:Record<string,unknown>;updatedAt:string};
export async function cacheBookerSnapshot(tenantId:string,patch:Record<string,unknown>):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{
  const tx=db.transaction(STORE,"readwrite"),store=tx.objectStore(STORE),key="snapshot-"+tenantId;
  const request=store.get(key);request.onsuccess=()=>{const old=request.result as BookerOfflineSnapshot|undefined;store.put({id:key,kind:"snapshot",tenantId,data:{...(old?.data||{}),...patch},updatedAt:new Date().toISOString()});};
  request.onerror=()=>reject(request.error||new Error("Offline Booker snapshot could not be read."));
  tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Offline Booker snapshot could not be saved."));
 });db.close();
}
export async function getBookerSnapshot(tenantId:string):Promise<BookerOfflineSnapshot|null>{
 const db=await openDb();const value=await new Promise<BookerOfflineSnapshot|null>((resolve,reject)=>{const tx=db.transaction(STORE,"readonly"),request=tx.objectStore(STORE).get("snapshot-"+tenantId);request.onsuccess=()=>resolve((request.result as BookerOfflineSnapshot)||null);request.onerror=()=>reject(request.error||new Error("Offline Booker snapshot could not be loaded."));});db.close();return value;
}
