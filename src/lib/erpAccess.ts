export const MODULE_KEYS=[
 "dashboard_management","sales_customer","order_booking","inventory","purchase_supplier",
 "accounts_finance","distribution_delivery","hr_payroll","reports_analytics","administration_security"
] as const;
export type ModulePermission={can_view:boolean;can_create:boolean;can_update:boolean;can_delete:boolean};
export type NavigationGroup={items:string[]};
export function resolveAllowedNavigation(
 role:string,
 nav:string[],
 roleAccess:Record<string,string[]>,
 groups:NavigationGroup[],
 overrides:Record<string,boolean>
):string[]{
 if(role==="owner")return nav;
 if(role==="admin")return nav.filter(item=>item!=="User Permissions");
 const baseline=roleAccess[role]||roleAccess.viewer||[];
 return nav.filter(item=>{
  if(item==="User Permissions")return false;
  const groupIndex=groups.findIndex(group=>group.items.includes(item));
  const key=MODULE_KEYS[groupIndex];
  return key&&Object.prototype.hasOwnProperty.call(overrides,key)?overrides[key]:baseline.includes(item);
 });
}
export function isModuleActionAllowed(permission:ModulePermission,action:keyof ModulePermission):boolean{
 if(action!=="can_view"&&!permission.can_view)return false;
 return permission[action];
}
export type BarcodeProduct={barcode?:string|null;sku?:string|null};
export function findProductByBarcodeOrSku<T extends BarcodeProduct>(raw:string,products:T[]):T|undefined{
 const code=raw.trim();if(!code)return undefined;
 return products.find(product=>String(product.barcode||"").trim()===code)
  ||products.find(product=>String(product.sku||"").trim().toLowerCase()===code.toLowerCase());
}
