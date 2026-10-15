drop policy if exists "admin manages categories" on public.menu_categories;
create policy "admin manages categories" on public.menu_categories for all to authenticated
using ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');
drop policy if exists "admin manages menu items" on public.menu_items;
create policy "admin manages menu items" on public.menu_items for all to authenticated
using ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');
drop policy if exists "admin manages tables" on public.cafe_tables;
create policy "admin manages tables" on public.cafe_tables for all to authenticated
using ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');
drop policy if exists "admin manages settings" on public.cafe_settings;
create policy "admin manages settings" on public.cafe_settings for all to authenticated
using ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');
drop policy if exists "admin manages orders" on public.orders;
create policy "admin manages orders" on public.orders for all to authenticated
using ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');
drop policy if exists "admin manages order items" on public.order_items;
create policy "admin manages order items" on public.order_items for all to authenticated
using ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');
drop policy if exists "admin manages reviews" on public.reviews;
create policy "admin manages reviews" on public.reviews for all to authenticated
using ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check ((auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');
grant select, insert, update, delete on public.menu_categories, public.menu_items, public.cafe_tables, public.cafe_settings, public.orders, public.order_items, public.reviews to authenticated;