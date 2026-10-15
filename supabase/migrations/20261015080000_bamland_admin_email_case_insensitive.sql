create policy "admin manages categories case insensitive" on public.menu_categories for all to authenticated
using (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');
create policy "admin manages menu items case insensitive" on public.menu_items for all to authenticated
using (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');
create policy "admin manages tables case insensitive" on public.cafe_tables for all to authenticated
using (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');
create policy "admin manages settings case insensitive" on public.cafe_settings for all to authenticated
using (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');
create policy "admin manages orders case insensitive" on public.orders for all to authenticated
using (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');
create policy "admin manages order items case insensitive" on public.order_items for all to authenticated
using (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');
create policy "admin manages reviews case insensitive" on public.reviews for all to authenticated
using (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');
create policy "admin manages menu images case insensitive" on storage.objects for all to authenticated
using (bucket_id = 'menu-images' and lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com')
with check (bucket_id = 'menu-images' and lower(auth.jwt() ->> 'email') = 'coffeebamland@gmail.com');