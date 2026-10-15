create or replace function public.sync_cafe_table_availability()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    update public.cafe_tables t
      set is_available = not exists (
        select 1 from public.orders o
        where o.table_id = t.id
          and o.status not in ('settled', 'cancelled')
      )
      where t.id = old.table_id;
    return old;
  end if;
  if TG_OP = 'UPDATE' then
    update public.cafe_tables t
      set is_available = not exists (
        select 1 from public.orders o
        where o.table_id = t.id
          and o.status not in ('settled', 'cancelled')
      )
      where t.id = old.table_id;
  end if;
  update public.cafe_tables t
    set is_available = not exists (
      select 1 from public.orders o
      where o.table_id = t.id
        and o.status not in ('settled', 'cancelled')
    )
    where t.id = new.table_id;
  return new;
end;
$$;
drop trigger if exists orders_sync_table_availability on public.orders;
create trigger orders_sync_table_availability
after insert or update of status, table_id or delete on public.orders
for each row execute function public.sync_cafe_table_availability();