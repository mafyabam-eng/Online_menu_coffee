do $$
declare v_table text;
begin
 foreach v_table in array array['menu_categories','menu_items','cafe_tables','cafe_settings','orders','order_items','reviews'] loop
  if not exists (
   select 1 from pg_publication_tables
   where pubname='supabase_realtime' and schemaname='public' and tablename=v_table
  ) then
   execute format('alter publication supabase_realtime add table public.%I',v_table);
  end if;
 end loop;
end $$;
