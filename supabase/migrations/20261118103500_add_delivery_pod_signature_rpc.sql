-- Restore the POD signature column and RPC to clean database replay.
alter table public.delivery_shop_visits
  add column if not exists proof_of_delivery_signature jsonb;

CREATE OR REPLACE FUNCTION public.save_delivery_pod_signature(p_delivery_id uuid, p_signature jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare v_delivery public.deliveries%rowtype;v_employee uuid;v_rows integer;
begin
 if auth.uid() is null then raise exception 'Authentication required.';end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id;
 if not found then raise exception 'Delivery was not found.';end if;
 if p_signature is null or jsonb_typeof(p_signature)<>'array' or jsonb_array_length(p_signature)<2 or jsonb_array_length(p_signature)>4000 then raise exception 'A valid customer signature drawing is required.';end if;
 if not public.has_tenant_role(v_delivery.tenant_id,array['owner','admin','manager','warehouse']) then
  select id into v_employee from public.employees where tenant_id=v_delivery.tenant_id and user_id=auth.uid() and employment_status='active' limit 1;
  if v_employee is null or v_delivery.delivery_man_employee_id is distinct from v_employee then raise exception 'You can only attach proof to your own assigned delivery.' using errcode='42501';end if;
 end if;
 if v_delivery.status not in ('delivered','partial','completed','returned') then raise exception 'Proof of delivery can only be attached after the delivery outcome is saved.';end if;
 update public.delivery_shop_visits set proof_of_delivery_signature=p_signature
 where tenant_id=v_delivery.tenant_id and delivery_id=v_delivery.id;
 get diagnostics v_rows=row_count;
 if v_rows<>1 then raise exception 'Delivery visit record is not available for this proof.';end if;
 return jsonb_build_object('success',true,'delivery_id',v_delivery.id,'signature_points',jsonb_array_length(p_signature));
end $function$


revoke all on function public.save_delivery_pod_signature(uuid,jsonb) from public, anon;
grant execute on function public.save_delivery_pod_signature(uuid,jsonb) to authenticated, service_role;
