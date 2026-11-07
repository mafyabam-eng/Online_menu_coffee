-- Restrict direct table/function privileges. RLS policies are intentionally unchanged.
do $$
declare r record;
begin
 for r in select schemaname,tablename from pg_tables where schemaname='public' loop
  execute format('revoke all privileges on table %I.%I from anon, authenticated',r.schemaname,r.tablename);
  execute format(
   'revoke all privileges (%s) on table %I.%I from anon, authenticated',
   (select string_agg(quote_ident(column_name),',' order by ordinal_position)
      from information_schema.columns
      where table_schema=r.schemaname and table_name=r.tablename),
   r.schemaname,r.tablename
  );
 end loop;
end $$;

grant select on public.menu_categories,public.menu_items,public.cafe_settings,public.cafe_tables to anon;
grant select,insert,update,delete on
 public.menu_categories,public.menu_items,public.cafe_tables,public.cafe_settings,
 public.orders,public.order_items,public.reviews,public.cafe_expenses,
 public.admin_data_archives,public.ledger_customers,public.ledger_transactions
to authenticated;

alter default privileges in schema public revoke all privileges on tables from anon,authenticated;
alter default privileges in schema public revoke execute on functions from public,anon,authenticated;

revoke execute on function public.sync_cafe_table_availability() from public,anon,authenticated;

do $
declare f record;
begin
 for f in
  select p.oid::regprocedure as signature
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
   'adjust_all_menu_prices','create_manual_order','save_manual_order_items',
   'set_order_discount','settle_order','record_ledger_payment',
   'delete_ledger_customer','get_admin_data_health','cleanup_admin_analytics_period'
  )
 loop
  execute format('revoke execute on function %s from public,anon',f.signature);
  execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $;

revoke all on function public.submit_anonymous_customer_feedback(uuid,uuid,integer,text) from public,authenticated;
grant execute on function public.submit_anonymous_customer_feedback(uuid,uuid,integer,text) to anon;

update storage.buckets
set file_size_limit=5242880,
    allowed_mime_types=array['image/jpeg','image/png','image/webp','image/avif','image/gif','font/woff2','font/woff']
where id='menu-images';

drop policy if exists "admin manages menu images" on storage.objects;
