create or replace function public.record_van_delivery_visit(
  p_delivery_id uuid,
  p_visit_status text,
  p_line_quantities jsonb,
  p_notes text,
  p_idempotency_key text,
  p_signature jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $function$
declare
  v_result jsonb;
begin
  if p_visit_status in ('delivered', 'short_delivered') then
    if p_signature is null
       or jsonb_typeof(p_signature) is distinct from 'array'
       or jsonb_array_length(p_signature) < 2
       or jsonb_array_length(p_signature) > 4000 then
      raise exception 'A customer signature is required for delivered or short-delivered outcomes.'
        using errcode = '23514';
    end if;
  end if;

  v_result := private.record_van_delivery_visit_internal(
    p_delivery_id,
    p_visit_status,
    p_line_quantities,
    p_notes,
    p_idempotency_key
  );

  if p_visit_status in ('delivered', 'short_delivered') then
    perform public.save_delivery_pod_signature(p_delivery_id, p_signature);
  end if;

  return v_result;
end;
$function$;

revoke all on function public.record_van_delivery_visit(uuid,text,jsonb,text,text,jsonb) from public, anon;
grant execute on function public.record_van_delivery_visit(uuid,text,jsonb,text,text,jsonb) to authenticated;
