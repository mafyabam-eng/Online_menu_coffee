create or replace function public.sync_cafe_table_availability()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if TG_OP = 'DELETE' then
    update public.cafe_tables t
      set is_available = not exists (
        select 1 from public.orders o
        where o.table_id = t.id
          and o.status not in ('settled', 'cancelled')
      )
      where t.id = old.table_id;
    return old;
  end if;

  if TG_OP = 'UPDATE' then
    update public.cafe_tables t
      set is_available = not exists (
        select 1 from public.orders o
        where o.table_id = t.id
          and o.status not in ('settled', 'cancelled')
      )
      where t.id = old.table_id;
  end if;

  update public.cafe_tables t
    set is_available = not exists (
      select 1 from public.orders o
      where o.table_id = t.id
        and o.status not in ('settled', 'cancelled')
    )
    where t.id = new.table_id;

  return new;
end;
$function$;

create or replace function public.create_manual_order(p_table_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_table public.cafe_tables%rowtype;
  v_settings public.cafe_settings%rowtype;
  v_order public.orders%rowtype;
  v_item_count integer;
  v_distinct_count integer;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_total numeric := 0;
  v_queue_wait integer := 0;
  v_order_wait integer := 0;
  v_lines jsonb := '[]'::jsonb;
begin
  if lower(coalesce(auth.jwt() ->> 'email', '')) <> 'coffeebamland@gmail.com' then
    raise exception 'admin_only';
  end if;

  if p_table_id is null or p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_order_input';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_items) x
    where coalesce(x ->> 'menu_item_id', '') !~* '^[0-9a-f-]{36}$'
       or coalesce(x ->> 'quantity', '') !~ '^[0-9]+$'
       or (x ->> 'quantity')::integer < 1
       or (x ->> 'quantity')::integer > 20
  ) then
    raise exception 'invalid_order_items';
  end if;

  select count(*), count(distinct (x ->> 'menu_item_id')::uuid)
    into v_item_count, v_distinct_count
  from jsonb_array_elements(p_items) x;

  if v_item_count <> v_distinct_count then
    raise exception 'duplicate_menu_items';
  end if;

  select * into v_table
  from public.cafe_tables
  where id = p_table_id
  for update;

  if not found or not v_table.is_active or not v_table.is_available then
    raise exception 'table_unavailable';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) x
    left join public.menu_items m on m.id = (x ->> 'menu_item_id')::uuid
    where m.id is null or not m.is_active
  ) then
    raise exception 'menu_item_unavailable';
  end if;

  select coalesce(sum(m.price * (x ->> 'quantity')::integer), 0),
         coalesce(sum(m.serving_minutes * (x ->> 'quantity')::integer), 0)
    into v_subtotal, v_order_wait
  from jsonb_array_elements(p_items) x
  join public.menu_items m on m.id = (x ->> 'menu_item_id')::uuid;

  select * into v_settings
  from public.cafe_settings
  where id = true;

  v_discount := round(v_subtotal * coalesce(v_settings.menu_discount_percent, 0) / 100);
  v_total := greatest(0, v_subtotal - v_discount);

  select coalesce(sum(per_order_wait), 0)::integer into v_queue_wait
  from (
    select o.id, coalesce(max(oi.serving_minutes * oi.quantity), 0) as per_order_wait
    from public.orders o
    join public.order_items oi on oi.order_id = o.id
    where o.status in ('pending', 'accepted', 'preparing')
    group by o.id
  ) q;

  insert into public.orders (
    table_id, status, subtotal, discount_amount, total,
    estimated_wait_minutes, customer_note
  ) values (
    p_table_id, 'pending', v_subtotal, v_discount, v_total,
    v_queue_wait + v_order_wait, ''
  )
  returning * into v_order;

  update public.cafe_tables
  set is_available = false
  where id = p_table_id;

  insert into public.order_items (
    order_id, menu_item_id, item_name, unit_price, quantity,
    serving_minutes, line_total
  )
  select
    v_order.id, m.id, m.name, m.price, (x ->> 'quantity')::integer,
    m.serving_minutes, m.price * (x ->> 'quantity')::integer
  from jsonb_array_elements(p_items) x
  join public.menu_items m on m.id = (x ->> 'menu_item_id')::uuid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', oi.id,
    'order_id', oi.order_id,
    'menu_item_id', oi.menu_item_id,
    'item_name', oi.item_name,
    'unit_price', oi.unit_price,
    'quantity', oi.quantity,
    'serving_minutes', oi.serving_minutes,
    'line_total', oi.line_total,
    'created_at', oi.created_at
  ) order by oi.created_at), '[]'::jsonb)
  into v_lines
  from public.order_items oi
  where oi.order_id = v_order.id;

  return jsonb_build_object(
    'order', jsonb_build_object(
      'id', v_order.id,
      'table_id', v_order.table_id,
      'status', v_order.status,
      'subtotal', v_order.subtotal,
      'discount_amount', v_order.discount_amount,
      'total', v_order.total,
      'estimated_wait_minutes', v_order.estimated_wait_minutes,
      'created_at', v_order.created_at
    ),
    'items', v_lines,
    'manual', true
  );
end;
$$;

revoke all on function public.create_manual_order(uuid, jsonb) from public;
revoke all on function public.create_manual_order(uuid, jsonb) from anon;
grant execute on function public.create_manual_order(uuid, jsonb) to authenticated;
