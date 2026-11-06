create table if not exists public.admin_data_archives (
 id uuid primary key default gen_random_uuid(),
 period_start date not null,
 period_end date not null,
 status text not null default 'planned' check (status in ('planned','exported','verified','approved','cleaned','failed')),
 report_file_path text,
 data_file_path text,
 metrics jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 verified_at timestamptz,
 approved_at timestamptz,
 cleaned_at timestamptz,
 created_by text,
 approved_by text,
 constraint admin_data_archives_period_check check (period_end >= period_start)
);
create index if not exists admin_data_archives_period_idx on public.admin_data_archives (period_start desc, period_end desc);
alter table public.admin_data_archives enable row level security;
create policy admin_data_archives_admin_only on public.admin_data_archives
 for all to authenticated
 using (lower(coalesce(auth.jwt()->>'email','')) = 'coffeebamland@gmail.com')
 with check (lower(coalesce(auth.jwt()->>'email','')) = 'coffeebamland@gmail.com');
