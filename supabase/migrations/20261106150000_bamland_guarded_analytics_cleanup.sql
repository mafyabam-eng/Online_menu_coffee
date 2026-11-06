create or replace function public.cleanup_admin_analytics_period(
  p_start_date date,
  p_end_date date,
  p_backup_confirmed boolean,
  p_it_present boolean
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_catalog
as $function$
declare
  v_order_ids uuid[] := array[]::uuid[];
  v_reviews integer := 0;
  v_items integer := 0;
  v_orders integer := 0;
  v_expenses integer := 0;
begin
  if lower(coalesce(auth.jwt()->>'email','')) <> 'coffeebamland@gmail.com' then
    raise exception 'admin_only';
  end if;
  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'invalid_period';
  end if;
  if p_backup_confirmed is distinct from true then
    raise exception 'backup_confirmation_required';
  end if;
  if p_it_present is distinct from true then
    raise exception 'it_presence_confirmation_required';
  end if;

  select coalesce(array_agg(o.id), array[]::uuid[])
    into v_order_ids
  from public.orders o
  where o.status in ('settled','cancelled')
    and o.created_at >= (p_start_date::timestamp at time zone 'Asia/Tehran')
    and o.created_at < ((p_end_date + 1)::timestamp at time zone 'Asia/Tehran');

  delete from public.reviews r where r.order_id = any(v_order_ids);
  get diagnostics v_reviews = row_count;

  delete from public.order_items oi where oi.order_id = any(v_order_ids);
  get diagnostics v_items = row_count;

  delete from public.orders o where o.id = any(v_order_ids);
  get diagnostics v_orders = row_count;

  delete from public.cafe_expenses e
  where e.expense_date between p_start_date and p_end_date;
  get diagnostics v_expenses = row_count;

  return jsonb_build_object(
    'period_start', p_start_date,
    'period_end', p_end_date,
    'deleted_orders', v_orders,
    'deleted_order_items', v_items,
    'deleted_reviews', v_reviews,
    'deleted_expenses', v_expenses,
    'completed_at', now(),
    'note', 'Only settled/cancelled orders and expenses in the selected Tehran-local date range were removed. Active orders and configuration/menu data were not touched.'
  );
end;
$function$;

revoke all on function public.cleanup_admin_analytics_period(date,date,boolean,boolean) from public, anon;
grant execute on function public.cleanup_admin_analytics_period(date,date,boolean,boolean) to authenticated;
