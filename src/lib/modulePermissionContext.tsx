import {createContext,useContext,type ReactNode} from "react";
export type ModuleActionPermission={can_view:boolean;can_create:boolean;can_update:boolean;can_delete:boolean};
const ModulePermissionContext=createContext<Record<string,ModuleActionPermission>>({});
export function ModulePermissionProvider({permissions,children}:{permissions:Record<string,ModuleActionPermission>;children:ReactNode}){
 return <ModulePermissionContext.Provider value={permissions}>{children}</ModulePermissionContext.Provider>;
}
export function useModuleAction(moduleKey:string,action:"view"|"create"|"update"|"delete",roleDefault:boolean){
 const permissions=useContext(ModulePermissionContext);
 const override=permissions[moduleKey];
 if(!override)return roleDefault;
 if(!override.can_view)return false;
 return override[action==="view"?"can_view":action==="create"?"can_create":action==="update"?"can_update":"can_delete"];
}
