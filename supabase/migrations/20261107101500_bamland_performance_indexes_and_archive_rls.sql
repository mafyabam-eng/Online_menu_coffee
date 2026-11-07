-- Index the time-ordered subsets used by the admin dashboard and reports.
create index if not exists orders_active_created_at_idx
 on public.orders (created_at desc)
 where status not in ('settled','cancelled');

create index if not exists orders_settled_created_at_idx
 on public.orders (created_at desc)
 where status='settled';

create index if not exists cafe_expenses_date_created_at_idx
 on public.cafe_expenses (expense_date desc, created_at desc);

-- Evaluate the administrator JWT once per statement, not once per row.
drop policy if exists admin_data_archives_admin_only on public.admin_data_archives;
create policy admin_data_archives_admin_only
 on public.admin_data_archives
 for all
 to authenticated
 using (lower(coalesce((select auth.jwt()->>'email'),''))='coffeebamland@gmail.com')
 with check (lower(coalesce((select auth.jwt()->>'email'),''))='coffeebamland@gmail.com');
