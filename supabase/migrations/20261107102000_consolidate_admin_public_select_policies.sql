-- Consolidate public/admin SELECT access to avoid multiple permissive SELECT policies.
-- The public menu/table policies continue to expose only active records; the admin
-- identity can also read inactive/unavailable records.

drop policy if exists "admin manages settings case insensitive" on public.cafe_settings;
create policy "admin inserts settings case insensitive" on public.cafe_settings
 for insert to authenticated
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin updates settings case insensitive" on public.cafe_settings
 for update to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com')
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin deletes settings case insensitive" on public.cafe_settings
 for delete to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');

drop policy if exists "admin manages tables case insensitive" on public.cafe_tables;
drop policy if exists "public read active tables" on public.cafe_tables;
create policy "public read active tables" on public.cafe_tables
 for select to anon, authenticated
 using ((is_active and is_available) or lower(coalesce((select auth.jwt()->>'email'),''))='coffeebamland@gmail.com');
create policy "admin inserts tables case insensitive" on public.cafe_tables
 for insert to authenticated
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin updates tables case insensitive" on public.cafe_tables
 for update to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com')
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin deletes tables case insensitive" on public.cafe_tables
 for delete to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');

drop policy if exists "admin manages categories case insensitive" on public.menu_categories;
drop policy if exists "public read active categories" on public.menu_categories;
create policy "public read active categories" on public.menu_categories
 for select to anon, authenticated
 using (is_active or lower(coalesce((select auth.jwt()->>'email'),''))='coffeebamland@gmail.com');
create policy "admin inserts categories case insensitive" on public.menu_categories
 for insert to authenticated
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin updates categories case insensitive" on public.menu_categories
 for update to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com')
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin deletes categories case insensitive" on public.menu_categories
 for delete to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');

drop policy if exists "admin manages menu items case insensitive" on public.menu_items;
drop policy if exists "public read active menu items" on public.menu_items;
create policy "public read active menu items" on public.menu_items
 for select to anon, authenticated
 using (is_active or lower(coalesce((select auth.jwt()->>'email'),''))='coffeebamland@gmail.com');
create policy "admin inserts menu items case insensitive" on public.menu_items
 for insert to authenticated
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin updates menu items case insensitive" on public.menu_items
 for update to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com')
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
create policy "admin deletes menu items case insensitive" on public.menu_items
 for delete to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
