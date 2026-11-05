create or replace function public.adjust_all_menu_prices(p_percent numeric, p_direction text)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $function$
declare
  affected integer;
  factor numeric;
begin
  if lower(coalesce(auth.jwt() ->> 'email', '')) <> 'coffeebamland@gmail.com' then
    raise exception 'Only the cafe administrator can adjust menu prices' using errcode = '42501';
  end if;

  if p_percent is null or p_percent <= 0 or p_percent > 100 then
    raise exception 'Percent must be greater than 0 and at most 100' using errcode = '22023';
  end if;

  if p_direction not in ('increase', 'decrease') then
    raise exception 'Direction must be increase or decrease' using errcode = '22023';
  end if;

  factor := case when p_direction = 'increase'
    then 1 + (p_percent / 100)
    else 1 - (p_percent / 100)
  end;

  update public.menu_items
  set price = greatest(1000::numeric, round((price::numeric * factor) / 1000) * 1000),
      updated_at = now()
  where id is not null;

  get diagnostics affected = row_count;
  return jsonb_build_object(
    'updated_count', affected,
    'percent', p_percent,
    'direction', p_direction,
    'rounding_unit', 1000,
    'minimum_price', 1000
  );
end;
$function$;
