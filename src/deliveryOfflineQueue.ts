export type OfflineDeliveryVisit = {
  id:string; idempotency_key:string; vehicle_number:string; user_id:string; tenant_id:string; delivery_id:string; delivery_man_employee_id:string; customer_id:string;
  visit_status:string; shops_visited:number; line_quantities:Array<Record<string,unknown>>;
  latitude?:number|null; longitude?:number|null;
  notes:string|null; created_by:string|null; queued_at:string; proof_of_delivery_signature?:Array<{x:number;y:number;move:boolean}>;
};
export type DeliverySnapshot = {id:string;tenant_id:string;user_id:string;data:Record<string,unknown>;updated_at:string};
const DB_NAME="ebs-pro-delivery-offline";const QUEUE="pending-visits";const SNAPSHOTS="delivery-snapshots";
function openDb():Promise<IDBDatabase>{
 return new Promise((resolve,reject)=>{const request=indexedDB.open(DB_NAME,2);request.onupgradeneeded=()=>{const db=request.result;if(!db.objectStoreNames.contains(QUEUE))db.createObjectStore(QUEUE,{keyPath:"id"});if(!db.objectStoreNames.contains(SNAPSHOTS))db.createObjectStore(SNAPSHOTS,{keyPath:"id"});};request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error||new Error("Delivery offline storage could not be opened."));});
}
export async function queueDeliveryVisit(visit:OfflineDeliveryVisit):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(QUEUE,"readwrite");tx.objectStore(QUEUE).put(visit);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Delivery visit could not be queued."));tx.onabort=()=>reject(tx.error||new Error("Delivery queue operation was cancelled."));});db.close();
}
export async function getQueuedDeliveryVisits(tenantId:string,userId:string):Promise<OfflineDeliveryVisit[]>{
 const db=await openDb();const rows=await new Promise<OfflineDeliveryVisit[]>((resolve,reject)=>{const tx=db.transaction(QUEUE,"readonly");const req=tx.objectStore(QUEUE).getAll();req.onsuccess=()=>resolve((req.result as OfflineDeliveryVisit[]).filter(x=>x.tenant_id===tenantId&&x.user_id===userId).sort((a,b)=>a.queued_at.localeCompare(b.queued_at)));req.onerror=()=>reject(req.error||new Error("Queued delivery visits could not be read."));});db.close();return rows;
}
export async function removeQueuedDeliveryVisit(id:string):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(QUEUE,"readwrite");tx.objectStore(QUEUE).delete(id);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Synced visit could not be removed."));});db.close();
}
export async function cacheDeliverySnapshot(tenantId:string,userId:string,data:Record<string,unknown>):Promise<void>{
 const db=await openDb();await new Promise<void>((resolve,reject)=>{const tx=db.transaction(SNAPSHOTS,"readwrite");tx.objectStore(SNAPSHOTS).put({id:tenantId+"-"+userId,tenant_id:tenantId,user_id:userId,data,updated_at:new Date().toISOString()});tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error||new Error("Delivery snapshot could not be saved."));});db.close();
}
export async function getDeliverySnapshot(tenantId:string,userId:string):Promise<DeliverySnapshot|null>{
 const db=await openDb();const result=await new Promise<DeliverySnapshot|null>((resolve,reject)=>{const tx=db.transaction(SNAPSHOTS,"readonly");const req=tx.objectStore(SNAPSHOTS).get(tenantId+"-"+userId);req.onsuccess=()=>resolve((req.result as DeliverySnapshot)||null);req.onerror=()=>reject(req.error||new Error("Delivery snapshot could not be loaded."));});db.close();return result;
}
