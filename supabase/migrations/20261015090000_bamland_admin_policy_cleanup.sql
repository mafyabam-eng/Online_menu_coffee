drop policy if exists "admin manages categories" on public.menu_categories;
drop policy if exists "admin manages menu items" on public.menu_items;
drop policy if exists "admin manages tables" on public.cafe_tables;
drop policy if exists "admin manages settings" on public.cafe_settings;
drop policy if exists "admin manages orders" on public.orders;
drop policy if exists "admin manages order items" on public.order_items;
drop policy if exists "admin manages reviews" on public.reviews;

alter policy "admin manages categories case insensitive" on public.menu_categories
using (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');
alter policy "admin manages menu items case insensitive" on public.menu_items
using (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');
alter policy "admin manages tables case insensitive" on public.cafe_tables
using (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');
alter policy "admin manages settings case insensitive" on public.cafe_settings
using (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');
alter policy "admin manages orders case insensitive" on public.orders
using (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');
alter policy "admin manages order items case insensitive" on public.order_items
using (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');
alter policy "admin manages reviews case insensitive" on public.reviews
using (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');
alter policy "admin manages menu images case insensitive" on storage.objects
using (bucket_id = 'menu-images' and lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com')
with check (bucket_id = 'menu-images' and lower((select auth.jwt() ->> 'email')) = 'coffeebamland@gmail.com');