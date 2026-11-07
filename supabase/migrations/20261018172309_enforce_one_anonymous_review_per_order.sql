create unique index if not exists reviews_one_per_order_uidx
 on public.reviews(order_id) where order_id is not null;
