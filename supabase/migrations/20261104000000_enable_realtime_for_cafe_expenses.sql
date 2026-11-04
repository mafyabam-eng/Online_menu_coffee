-- Keep expense changes visible to the authenticated admin analytics screen.
-- RLS remains enabled and existing admin policies continue to control row access.
alter publication supabase_realtime add table public.cafe_expenses;
