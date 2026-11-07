create table if not exists public.cafe_expenses (
 id uuid primary key default gen_random_uuid(),
 expense_date date not null,
 title text not null,
 amount numeric(14,2) not null,
 details text not null default '',
 created_at timestamptz not null default now(),
 created_by text
);
do $
begin
 if not exists(select 1 from pg_constraint where conrelid='public.cafe_expenses'::regclass and conname='cafe_expenses_amount_check') then
  alter table public.cafe_expenses add constraint cafe_expenses_amount_check check(amount>0);
 end if;
 if not exists(select 1 from pg_constraint where conrelid='public.cafe_expenses'::regclass and conname='cafe_expenses_title_check') then
  alter table public.cafe_expenses add constraint cafe_expenses_title_check
   check(length(trim(title)) between 1 and 160);
 end if;
end $;
create index if not exists cafe_expenses_date_created_at_idx
 on public.cafe_expenses(expense_date desc,created_at desc);
alter table public.cafe_expenses enable row level security;
drop policy if exists "admin manages cafe expenses case insensitive" on public.cafe_expenses;
create policy "admin manages cafe expenses case insensitive"
 on public.cafe_expenses for all to authenticated
 using (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com')
 with check (lower((select auth.jwt()->>'email'))='coffeebamland@gmail.com');
grant select,insert,update,delete on public.cafe_expenses to authenticated;
