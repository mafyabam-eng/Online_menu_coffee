create table if not exists public.order_rate_limits (
 key text not null,
 window_start timestamptz not null,
 count integer not null default 0 check(count>=0),
 primary key(key,window_start)
);
alter table public.order_rate_limits enable row level security;
revoke all privileges on public.order_rate_limits from public,anon,authenticated;
