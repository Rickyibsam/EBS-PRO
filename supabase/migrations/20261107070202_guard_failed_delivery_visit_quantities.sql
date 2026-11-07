create or replace function private.guard_failed_delivery_visit_quantities()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  if new.visit_status in ('not_available', 'refused') then
    if jsonb_typeof(new.line_quantities) is distinct from 'array' then
      raise exception 'Failed or unavailable visits must have a valid zero-quantity report.'
        using errcode = '23514';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(new.line_quantities) as item(value)
      where coalesce((item.value ->> 'delivered_quantity_base')::numeric, 0) <> 0
         or coalesce((item.value ->> 'market_return_quantity_base')::numeric, 0) <> 0
    ) then
      raise exception 'A not-available or refused visit cannot post delivered or returned quantities.'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.guard_failed_delivery_visit_quantities() from public, anon, authenticated;

drop trigger if exists guard_failed_delivery_visit_quantities on public.delivery_shop_visits;
create trigger guard_failed_delivery_visit_quantities
before insert or update of visit_status, line_quantities
on public.delivery_shop_visits
for each row
execute function private.guard_failed_delivery_visit_quantities();
