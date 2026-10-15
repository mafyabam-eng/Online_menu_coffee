-- BAMLAND initial operational schema
create extension if not exists pgcrypto;

create table if not exists public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.menu_categories(id) on delete set null,
  name text not null,
  description text not null default '',
  price numeric(12,2) not null default 0 check (price >= 0),
  serving_minutes integer not null default 0 check (serving_minutes >= 0),
  image_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.cafe_tables (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  qr_token uuid not null unique default gen_random_uuid(),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  table_id uuid not null references public.cafe_tables(id),
  status text not null default 'pending' check (status in ('pending','accepted','preparing','ready','served','settled','cancelled')),
  customer_session_token uuid not null default gen_random_uuid(),
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  estimated_wait_minutes integer not null default 0 check (estimated_wait_minutes >= 0),
  customer_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  settled_at timestamptz
);
create unique index if not exists orders_one_active_per_table on public.orders(table_id) where status not in ('settled','cancelled');
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  item_name text not null,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  serving_minutes integer not null default 0 check (serving_minutes >= 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete set null,
  rating integer check (rating between 1 and 5),
  message text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.cafe_settings (
  id boolean primary key default true check (id),
  welcome_message text not null default 'به بام‌لند خوش آمدید',
  menu_discount_percent numeric(5,2) not null default 0 check (menu_discount_percent between 0 and 100),
  updated_at timestamptz not null default now()
);
insert into public.cafe_settings(id) values(true) on conflict(id) do nothing;

alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.cafe_tables enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.reviews enable row level security;
alter table public.cafe_settings enable row level security;

drop policy if exists "public read active categories" on public.menu_categories;
create policy "public read active categories" on public.menu_categories for select to anon, authenticated using (is_active);
drop policy if exists "public read active menu items" on public.menu_items;
create policy "public read active menu items" on public.menu_items for select to anon, authenticated using (is_active);
drop policy if exists "public read active tables" on public.cafe_tables;
create policy "public read active tables" on public.cafe_tables for select to anon, authenticated using (is_active);
drop policy if exists "public read cafe settings" on public.cafe_settings;
create policy "public read cafe settings" on public.cafe_settings for select to anon, authenticated using (true);

revoke all on public.orders from anon, authenticated;
revoke all on public.order_items from anon, authenticated;
revoke all on public.reviews from anon, authenticated;
revoke insert, update, delete on public.menu_categories from anon, authenticated;
revoke insert, update, delete on public.menu_items from anon, authenticated;
revoke insert, update, delete on public.cafe_tables from anon, authenticated;
revoke insert, update, delete on public.cafe_settings from anon, authenticated;
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
