-- Keep expense changes visible to the authenticated admin analytics screen.
-- RLS remains enabled and existing admin policies continue to control row access.
do $$
begin
 if not exists (
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='cafe_expenses'
 ) then
  alter publication supabase_realtime add table public.cafe_expenses;
 end if;
end $$;
