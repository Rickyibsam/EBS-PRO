create or replace function public.record_van_delivery_visit(
  p_delivery_id uuid,
  p_visit_status text,
  p_line_quantities jsonb,
  p_notes text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $function$
begin
  if p_visit_status in ('delivered', 'short_delivered') then
    raise exception 'A customer signature is required; use the signature-aware delivery workflow.'
      using errcode = '23514';
  end if;

  return private.record_van_delivery_visit_internal(
    p_delivery_id,
    p_visit_status,
    p_line_quantities,
    p_notes,
    p_idempotency_key
  );
end;
$function$;
