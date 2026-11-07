create or replace function public.customer_place_or_extend_order(
 p_table_id uuid,p_session_token uuid,p_items jsonb,p_note text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
 v_table public.cafe_tables%rowtype;
 v_order public.orders%rowtype;
 v_settings public.cafe_settings%rowtype;
 v_item record;
 v_existing public.order_items%rowtype;
 v_menu public.menu_items%rowtype;
 v_subtotal numeric:=0;
 v_menu_discount numeric:=0;
 v_order_discount numeric:=0;
 v_discount numeric:=0;
 v_total numeric:=0;
 v_added_wait integer:=0;
 v_queue_wait integer:=0;
 v_items jsonb:='[]'::jsonb;
 v_count integer;
 v_resumed boolean:=false;
begin
 if p_table_id is null or p_session_token is null or p_items is null
    or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1
    or jsonb_array_length(p_items)>30 then
  raise exception 'invalid_items' using errcode='22023';
 end if;
 if exists(
  select 1 from jsonb_array_elements(p_items) x
  where coalesce(x->>'menu_item_id','') !~* '^[0-9a-f-]{36}$'
     or coalesce(x->>'quantity','') !~ '^[0-9]+$'
     or (x->>'quantity')::integer not between 1 and 20
 ) then raise exception 'invalid_items' using errcode='22023'; end if;

 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_session_token::text,0));
 select * into v_table from public.cafe_tables where id=p_table_id for update;
 if not found or not v_table.is_active then raise exception 'table_unavailable' using errcode='22023'; end if;

 if exists(select 1 from public.orders o
   where o.customer_session_token=p_session_token
     and o.table_id<>p_table_id and o.status not in ('settled','cancelled')) then
  raise exception 'session_has_other_active_order' using errcode='23505';
 end if;

 select * into v_order from public.orders
 where table_id=p_table_id and status not in ('settled','cancelled')
 for update;

 if found then
  if v_order.customer_session_token<>p_session_token then
   raise exception 'table_occupied' using errcode='23505';
  end if;
  if v_order.status not in ('pending','accepted') then
   raise exception 'order_not_editable' using errcode='55000';
  end if;
  v_resumed:=true;
 end if;

 select * into v_settings from public.cafe_settings where id=true;
 if not found then raise exception 'settings_unavailable'; end if;

 for v_item in
  select (x->>'menu_item_id')::uuid as menu_item_id,sum((x->>'quantity')::integer)::integer as quantity
  from jsonb_array_elements(p_items) x group by (x->>'menu_item_id')::uuid
 loop
  select * into v_menu from public.menu_items where id=v_item.menu_item_id and is_active;
  if not found then raise exception 'menu_item_unavailable' using errcode='22023'; end if;
  v_added_wait:=v_added_wait+coalesce(v_menu.serving_minutes,0)*v_item.quantity;
  if v_resumed then
   select * into v_existing from public.order_items
    where order_id=v_order.id and menu_item_id=v_menu.id for update;
   if found then
    update public.order_items set
      item_name=v_menu.name,unit_price=v_menu.price,
      quantity=v_existing.quantity+v_item.quantity,
      serving_minutes=v_menu.serving_minutes,
      line_total=v_menu.price*(v_existing.quantity+v_item.quantity)
    where id=v_existing.id;
   else
    insert into public.order_items(order_id,menu_item_id,item_name,unit_price,quantity,serving_minutes,line_total)
    values(v_order.id,v_menu.id,v_menu.name,v_menu.price,v_item.quantity,v_menu.serving_minutes,v_menu.price*v_item.quantity);
   end if;
  else
   -- The new order row is inserted below; item rows are staged in JSON.
   v_items:=v_items||jsonb_build_array(jsonb_build_object(
    'menu_item_id',v_menu.id,'item_name',v_menu.name,'unit_price',v_menu.price,
    'quantity',v_item.quantity,'serving_minutes',v_menu.serving_minutes,
    'line_total',v_menu.price*v_item.quantity));
  end if;
 end loop;

 if v_resumed then
  select coalesce(sum(line_total),0) into v_subtotal from public.order_items where order_id=v_order.id;
  v_menu_discount:=round(v_subtotal*coalesce(v_settings.menu_discount_percent,0)/100);
  v_order_discount:=round(greatest(0,v_subtotal-v_menu_discount)*coalesce(v_order.order_discount_percent,0)/100);
  v_discount:=v_menu_discount+v_order_discount;
  v_total:=greatest(0,v_subtotal-v_discount);
  update public.orders set subtotal=v_subtotal,menu_discount_amount=v_menu_discount,
   order_discount_amount=v_order_discount,discount_amount=v_discount,total=v_total,
   estimated_wait_minutes=coalesce(v_order.estimated_wait_minutes,0)+v_added_wait,
   customer_note=case when coalesce(trim(p_note),'')='' then customer_note
    when customer_note='' then left(trim(p_note),500)
    else left(customer_note||E'\n'||trim(p_note),500) end,
   updated_at=now() where id=v_order.id returning * into v_order;
 else
  select coalesce(sum((x->>'serving_minutes')::integer*(x->>'quantity')::integer),0)
   into v_added_wait from jsonb_array_elements(v_items) x;
  select coalesce(sum(mx),0)::integer into v_queue_wait from (
   select max(oi.serving_minutes*oi.quantity) mx
   from public.orders o join public.order_items oi on oi.order_id=o.id
   where o.status in ('pending','accepted','preparing') group by o.id
  ) q;
  select coalesce(sum((x->>'line_total')::numeric),0) into v_subtotal from jsonb_array_elements(v_items) x;
  v_menu_discount:=round(v_subtotal*coalesce(v_settings.menu_discount_percent,0)/100);
  v_order_discount:=0;v_discount:=v_menu_discount;v_total:=greatest(0,v_subtotal-v_discount);
  insert into public.orders(table_id,status,customer_session_token,subtotal,menu_discount_amount,
   order_discount_percent,order_discount_amount,discount_amount,total,estimated_wait_minutes,customer_note,is_manual)
  values(p_table_id,'pending',p_session_token,v_subtotal,v_menu_discount,0,0,v_discount,v_total,
   v_queue_wait+v_added_wait,left(coalesce(p_note,''),500),false) returning * into v_order;
  insert into public.order_items(order_id,menu_item_id,item_name,unit_price,quantity,serving_minutes,line_total)
  select v_order.id,(x->>'menu_item_id')::uuid,x->>'item_name',(x->>'unit_price')::numeric,
   (x->>'quantity')::integer,(x->>'serving_minutes')::integer,(x->>'line_total')::numeric
  from jsonb_array_elements(v_items) x;
 end if;

 select coalesce(jsonb_agg(to_jsonb(oi) order by oi.created_at),'[]'::jsonb)
 into v_items from public.order_items oi where oi.order_id=v_order.id;
 return jsonb_build_object('order',to_jsonb(v_order),'items',v_items,'resumed',v_resumed,'items_added',v_resumed);
end;
$$;
revoke all on function public.customer_place_or_extend_order(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.customer_place_or_extend_order(uuid,uuid,jsonb,text) to service_role;
