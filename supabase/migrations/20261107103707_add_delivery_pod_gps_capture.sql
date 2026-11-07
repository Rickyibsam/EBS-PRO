-- Persist deliveryman GPS coordinates atomically with the delivery visit and POD workflow.
create or replace function private.attach_delivery_visit_gps_internal(
  p_visit_id uuid, p_delivery_id uuid, p_latitude numeric, p_longitude numeric
) returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare v_tenant_id uuid; v_employee_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode = '42501'; end if;
  if p_latitude is null or p_longitude is null or p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Valid GPS latitude and longitude are required.' using errcode = '22023';
  end if;
  select d.tenant_id,d.delivery_man_employee_id into v_tenant_id,v_employee_id
  from public.deliveries d where d.id=p_delivery_id for update;
  if v_tenant_id is null then raise exception 'Delivery not found.'; end if;
  if not public.has_tenant_role(v_tenant_id,array['owner','admin','manager'])
     and not exists(select 1 from public.employees e where e.id=v_employee_id and e.tenant_id=v_tenant_id and e.user_id=auth.uid() and e.employment_status='active') then
    raise exception 'You can only attach GPS to your own assigned delivery.' using errcode = '42501';
  end if;
  update public.delivery_shop_visits v
  set latitude=coalesce(v.latitude,p_latitude),longitude=coalesce(v.longitude,p_longitude)
  where v.id=p_visit_id and v.tenant_id=v_tenant_id and v.delivery_id=p_delivery_id;
  if not found then raise exception 'Delivery visit was not found for GPS attachment.'; end if;
end;
$$;
revoke all on function private.attach_delivery_visit_gps_internal(uuid,uuid,numeric,numeric) from public,anon;
grant execute on function private.attach_delivery_visit_gps_internal(uuid,uuid,numeric,numeric) to authenticated;

create or replace function public.record_van_delivery_visit(
 p_delivery_id uuid,p_visit_status text,p_line_quantities jsonb,p_notes text,
 p_idempotency_key text,p_signature jsonb,p_latitude numeric,p_longitude numeric
) returns jsonb language plpgsql
set search_path=pg_catalog,public,auth,private
as $$
declare v_result jsonb;
begin
 if (p_latitude is null)<>(p_longitude is null) then raise exception 'GPS latitude and longitude must be supplied together.' using errcode='22023'; end if;
 if p_latitude is not null and (p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180) then
  raise exception 'GPS coordinates are outside valid ranges.' using errcode='22023';
 end if;
 if p_visit_status in ('delivered','short_delivered') then
  if p_signature is null or jsonb_typeof(p_signature) is distinct from 'array' or jsonb_array_length(p_signature)<2 or jsonb_array_length(p_signature)>4000 then
   raise exception 'A customer signature is required for delivered or short-delivered outcomes.' using errcode='23514';
  end if;
 end if;
 v_result:=private.record_van_delivery_visit_internal(p_delivery_id,p_visit_status,p_line_quantities,p_notes,p_idempotency_key);
 if p_latitude is not null then
  perform private.attach_delivery_visit_gps_internal((v_result->>'visit_id')::uuid,p_delivery_id,p_latitude,p_longitude);
 end if;
 if p_visit_status in ('delivered','short_delivered') then perform public.save_delivery_pod_signature(p_delivery_id,p_signature); end if;
 return v_result;
end;
$$;
revoke all on function public.record_van_delivery_visit(uuid,text,jsonb,text,text,jsonb,numeric,numeric) from public,anon;
grant execute on function public.record_van_delivery_visit(uuid,text,jsonb,text,text,jsonb,numeric,numeric) to authenticated;

-- Preserve the existing six-argument signature for older clients; it records no GPS.
create or replace function public.record_van_delivery_visit(
 p_delivery_id uuid,p_visit_status text,p_line_quantities jsonb,p_notes text,p_idempotency_key text,p_signature jsonb
) returns jsonb language sql set search_path=pg_catalog,public,private
as $$ select public.record_van_delivery_visit(p_delivery_id,p_visit_status,p_line_quantities,p_notes,p_idempotency_key,p_signature,null::numeric,null::numeric); $$;
revoke all on function public.record_van_delivery_visit(uuid,text,jsonb,text,text,jsonb) from public,anon;
grant execute on function public.record_van_delivery_visit(uuid,text,jsonb,text,text,jsonb) to authenticated;
