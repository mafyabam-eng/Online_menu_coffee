create table if not exists public.order_rate_limits (
 key text not null,
 window_start timestamptz not null,
 count integer not null default 0 check(count>=0),
 primary key(key,window_start)
);
alter table public.order_rate_limits enable row level security;
revoke all privileges on public.order_rate_limits from public,anon,authenticated;

revoke select on public.cafe_tables from anon;
grant select (id,name,sort_order,is_active,is_available) on public.cafe_tables to anon;

create or replace function public.consume_order_rate_limit(p_key text,p_window_start timestamptz)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
 insert into public.order_rate_limits(key,window_start,count)
 values(p_key,p_window_start,1)
 on conflict(key,window_start) do update
 set count=public.order_rate_limits.count+1
 returning count into v_count;
 return v_count;
end;
$$;
revoke all on function public.consume_order_rate_limit(text,timestamptz) from public,anon,authenticated;
grant execute on function public.consume_order_rate_limit(text,timestamptz) to service_role;
