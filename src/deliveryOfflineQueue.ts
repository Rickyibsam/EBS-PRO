export type OfflineDeliveryVisit = {
  id: string;
  tenant_id: string;
  delivery_id: string;
  delivery_man_employee_id: string;
  customer_id: string;
  visit_status: string;
  shops_visited: number;
  line_quantities: Array<Record<string, unknown>>;
  notes: string | null;
  created_by: string | null;
  queued_at: string;
};
const DB_NAME = "ebs-pro-delivery-offline";
const STORE = "pending-visits";
function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve,reject) => {
    const request = indexedDB.open(DB_NAME,1);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(STORE)) request.result.createObjectStore(STORE,{keyPath:"id"});
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("Delivery offline storage could not be opened."));
  });
}
export async function queueDeliveryVisit(visit: OfflineDeliveryVisit): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve,reject) => {
    const tx = db.transaction(STORE,"readwrite");
    tx.objectStore(STORE).put(visit);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error || new Error("Delivery visit could not be queued."));
    tx.onabort = () => reject(tx.error || new Error("Delivery visit queue operation was cancelled."));
  });
  db.close();
}
export async function getQueuedDeliveryVisits(tenantId:string): Promise<OfflineDeliveryVisit[]> {
  const db = await openDb();
  const rows = await new Promise<OfflineDeliveryVisit[]>((resolve,reject) => {
    const tx = db.transaction(STORE,"readonly");
    const req = tx.objectStore(STORE).getAll();
    req.onsuccess = () => resolve((req.result as OfflineDeliveryVisit[]).filter(x=>x.tenant_id===tenantId).sort((a,b)=>a.queued_at.localeCompare(b.queued_at)));
    req.onerror = () => reject(req.error || new Error("Queued delivery visits could not be read."));
  });
  db.close();
  return rows;
}
export async function removeQueuedDeliveryVisit(id:string): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve,reject) => {
    const tx = db.transaction(STORE,"readwrite");
    tx.objectStore(STORE).delete(id);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error || new Error("Synced delivery visit could not be removed."));
  });
  db.close();
}
