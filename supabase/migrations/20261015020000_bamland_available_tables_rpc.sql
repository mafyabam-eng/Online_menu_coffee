create or replace function public.get_available_tables()
returns table(id uuid, name text, qr_token uuid)
language sql
security definer
set search_path = ''
stable
as $$
  select t.id, t.name, t.qr_token
  from public.cafe_tables as t
  where t.is_active
    and not exists (
      select 1 from public.orders as o
      where o.table_id = t.id
        and o.status not in ('settled', 'cancelled')
    )
  order by t.sort_order, t.name;
$$;

revoke all on function public.get_available_tables() from public;
grant execute on function public.get_available_tables() to anon, authenticated;
