create table if not exists public.cafe_expenses (
 id uuid primary key default gen_random_uuid(),
 expense_date date not null,
 title text not null,
 amount numeric not null,
 details text not null default '',
 created_at timestamptz not null default now(),
 created_by text
);
create index if not exists cafe_expenses_date_created_at_idx
 on public.cafe_expenses(expense_date desc,created_at desc);
alter table public.cafe_expenses enable row level security;
drop policy if exists "admin manages cafe expenses case insensitive" on public.cafe_expenses;
create policy "admin manages cafe expenses case insensitive"
 on public.cafe_expenses for all to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com')
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
grant select,insert,update,delete on public.cafe_expenses to authenticated;
do $$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='cafe_expenses') then
  alter publication supabase_realtime add table public.cafe_expenses;
 end if;
end $$;
