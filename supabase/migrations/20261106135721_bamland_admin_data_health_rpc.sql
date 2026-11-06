create or replace function public.get_admin_data_health()
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_catalog
as $$
declare
 v_db_bytes bigint;
 v_tables jsonb;
 v_counts jsonb;
begin
 if lower(coalesce(auth.jwt()->>'email','')) <> 'coffeebamland@gmail.com' then
  raise exception 'admin_only';
 end if;
 select pg_database_size(current_database()) into v_db_bytes;
 select coalesce(jsonb_agg(jsonb_build_object(
  'table_name',t.table_name,'row_count',t.row_count,'total_bytes',t.total_bytes
 ) order by t.total_bytes desc),'[]'::jsonb)
 into v_tables
 from (
  select x.table_name,x.row_count,
   pg_total_relation_size(to_regclass('public.'||quote_ident(x.table_name)))::bigint as total_bytes
  from (values
   ('menu_categories',(select count(*) from public.menu_categories)),
   ('menu_items',(select count(*) from public.menu_items)),
   ('cafe_tables',(select count(*) from public.cafe_tables)),
   ('orders',(select count(*) from public.orders)),
   ('order_items',(select count(*) from public.order_items)),
   ('reviews',(select count(*) from public.reviews)),
   ('cafe_settings',(select count(*) from public.cafe_settings)),
   ('cafe_expenses',(select count(*) from public.cafe_expenses)),
   ('admin_data_archives',(select count(*) from public.admin_data_archives))
  ) as x(table_name,row_count)
 ) t;
 select jsonb_build_object(
  'orders',(select count(*) from public.orders),
  'open_orders',(select count(*) from public.orders where status in ('pending','accepted','preparing','ready','served')),
  'settled_orders',(select count(*) from public.orders where status='settled'),
  'cancelled_orders',(select count(*) from public.orders where status='cancelled'),
  'order_items',(select count(*) from public.order_items),
  'reviews',(select count(*) from public.reviews),
  'expenses',(select count(*) from public.cafe_expenses),
  'menu_items',(select count(*) from public.menu_items),
  'active_menu_items',(select count(*) from public.menu_items where is_active),
  'archives',(select count(*) from public.admin_data_archives)
 ) into v_counts;
 return jsonb_build_object(
  'database_bytes',v_db_bytes,
  'database_pretty',pg_size_pretty(v_db_bytes),
  'tables',v_tables,
  'counts',v_counts,
  'measured_at',now(),
  'storage_quota_note','Storage quota and plan limits are not exposed by this database-level report.'
 );
end;
$$;
revoke all on function public.get_admin_data_health() from public;
revoke all on function public.get_admin_data_health() from anon;
grant execute on function public.get_admin_data_health() to authenticated;
