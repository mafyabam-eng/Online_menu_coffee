insert into storage.buckets (id, name, public)
values ('menu-images', 'menu-images', true)
on conflict (id) do update set public = true;
drop policy if exists "public reads menu images" on storage.objects;
create policy "public reads menu images" on storage.objects for select to anon, authenticated
using (bucket_id = 'menu-images');
drop policy if exists "admin manages menu images" on storage.objects;
create policy "admin manages menu images" on storage.objects for all to authenticated
using (bucket_id = 'menu-images' and (auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com')
with check (bucket_id = 'menu-images' and (auth.jwt() ->> 'email') = 'CoffeeBamland@gmail.com');