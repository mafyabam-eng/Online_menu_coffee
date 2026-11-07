-- Ledger accounts and order controls for Bamland.

create table if not exists public.ledger_customers (
 id uuid primary key default gen_random_uuid(),
 first_name text not null check (length(btrim(first_name)) between 1 and 100),
 last_name text not null check (length(btrim(last_name)) between 1 and 100),
 code char(4) not null unique check (code ~ '^[0-9]{4}$'),
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.ledger_transactions (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.ledger_customers(id) on delete cascade,
 transaction_type text not null check (transaction_type in ('order_charge','payment')),
 amount numeric(14,2) not null check (amount > 0),
 order_id uuid,
 description text not null default '',
 created_at timestamptz not null default now(),
 created_by text
);

create index if not exists ledger_transactions_customer_created_idx on public.ledger_transactions(customer_id,created_at desc);

create unique index if not exists ledger_transactions_one_order_charge_idx on public.ledger_transactions(order_id) where order_id is not null and transaction_type='order_charge';

alter table public.orders
 add column if not exists is_manual boolean not null default false,
 add column if not exists ledger_customer_id uuid references public.ledger_customers(id) on delete set null,
 add column if not exists ledger_customer_name text,
 add column if not exists settlement_method text not null default 'cash',
 add column if not exists menu_discount_amount numeric(14,2) not null default 0,
 add column if not exists order_discount_percent numeric(5,2) not null default 0,
 add column if not exists order_discount_amount numeric(14,2) not null default 0;

update public.orders set menu_discount_amount=discount_amount where menu_discount_amount=0 and discount_amount>0;

alter table public.orders
 drop constraint if exists orders_order_discount_percent_check,
 add constraint orders_order_discount_percent_check check (order_discount_percent between 0 and 100),
 drop constraint if exists orders_settlement_method_check,
 add constraint orders_settlement_method_check check (settlement_method in ('cash','ledger')),
 drop constraint if exists orders_menu_discount_amount_check,
 add constraint orders_menu_discount_amount_check check (menu_discount_amount>=0),
 drop constraint if exists orders_order_discount_amount_check,
 add constraint orders_order_discount_amount_check check (order_discount_amount>=0);

alter table public.ledger_customers enable row level security;

alter table public.ledger_transactions enable row level security;

create policy "admin manages ledger customers" on public.ledger_customers for all to authenticated
 using (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com')
 with check (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com');

create policy "admin manages ledger transactions" on public.ledger_transactions for all to authenticated
 using (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com')
 with check (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com');

grant select,insert,update,delete on public.ledger_customers to authenticated;

grant select,insert,update,delete on public.ledger_transactions to authenticated;

CREATE OR REPLACE FUNCTION public.create_manual_order(p_table_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_table public.cafe_tables%rowtype;
  v_settings public.cafe_settings%rowtype;
  v_order public.orders%rowtype;
  v_item_count integer;
  v_distinct_count integer;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_total numeric := 0;
  v_queue_wait integer := 0;
  v_order_wait integer := 0;
  v_lines jsonb := '[]'::jsonb;
begin
  if lower(coalesce(auth.jwt() ->> 'email', '')) <> 'coffeebamland@gmail.com' then
    raise exception 'admin_only';
  end if;
  if p_table_id is null or p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 30 then
    raise exception 'invalid_order_input';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) x
    where coalesce(x ->> 'menu_item_id', '') !~* '^[0-9a-f-]{36}$'
       or coalesce(x ->> 'quantity', '') !~ '^[0-9]+$'
       or (x ->> 'quantity')::integer < 1
       or (x ->> 'quantity')::integer > 20
  ) then raise exception 'invalid_order_items'; end if;
  select count(*), count(distinct (x ->> 'menu_item_id')::uuid)
    into v_item_count, v_distinct_count
  from jsonb_array_elements(p_items) x;
  if v_item_count <> v_distinct_count then raise exception 'duplicate_menu_items'; end if;

  select * into v_table from public.cafe_tables where id=p_table_id for update;
  if not found or not v_table.is_active or not v_table.is_available then
    raise exception 'table_unavailable';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) x
    left join public.menu_items m on m.id=(x->>'menu_item_id')::uuid
    where m.id is null or not m.is_active
  ) then raise exception 'menu_item_unavailable'; end if;

  select coalesce(sum(m.price*(x->>'quantity')::integer),0),
         coalesce(sum(m.serving_minutes*(x->>'quantity')::integer),0)
    into v_subtotal,v_order_wait
  from jsonb_array_elements(p_items) x
  join public.menu_items m on m.id=(x->>'menu_item_id')::uuid;

  select * into v_settings from public.cafe_settings where id=true;
  v_discount:=round(v_subtotal*coalesce(v_settings.menu_discount_percent,0)/100);
  v_total:=greatest(0,v_subtotal-v_discount);

  select coalesce(sum(per_order_wait),0)::integer into v_queue_wait
  from (
    select o.id,coalesce(max(oi.serving_minutes*oi.quantity),0) as per_order_wait
    from public.orders o join public.order_items oi on oi.order_id=o.id
    where o.status in ('pending','accepted','preparing')
    group by o.id
  ) q;

  insert into public.orders (
    table_id,status,subtotal,discount_amount,total,estimated_wait_minutes,
    customer_note,is_manual,menu_discount_amount,order_discount_percent,order_discount_amount
  ) values (
    p_table_id,'pending',v_subtotal,v_discount,v_total,
    v_queue_wait+v_order_wait,'',true,v_discount,0,0
  ) returning * into v_order;

  update public.cafe_tables set is_available=false where id=p_table_id;

  insert into public.order_items (
    order_id,menu_item_id,item_name,unit_price,quantity,serving_minutes,line_total
  )
  select v_order.id,m.id,m.name,m.price,(x->>'quantity')::integer,
         m.serving_minutes,m.price*(x->>'quantity')::integer
  from jsonb_array_elements(p_items) x
  join public.menu_items m on m.id=(x->>'menu_item_id')::uuid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',oi.id,'order_id',oi.order_id,'menu_item_id',oi.menu_item_id,
    'item_name',oi.item_name,'unit_price',oi.unit_price,'quantity',oi.quantity,
    'serving_minutes',oi.serving_minutes,'line_total',oi.line_total,'created_at',oi.created_at
  ) order by oi.created_at),'[]'::jsonb)
  into v_lines from public.order_items oi where oi.order_id=v_order.id;

  return jsonb_build_object(
    'order',jsonb_build_object(
      'id',v_order.id,'table_id',v_order.table_id,'status',v_order.status,
      'subtotal',v_order.subtotal,'discount_amount',v_order.discount_amount,
      'total',v_order.total,'estimated_wait_minutes',v_order.estimated_wait_minutes,
      'created_at',v_order.created_at,'is_manual',true
    ),
    'items',v_lines,'manual',true
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.save_manual_order_items(p_order_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_order public.orders%rowtype;
  v_settings public.cafe_settings%rowtype;
  v_subtotal numeric:=0;
  v_menu_discount numeric:=0;
  v_order_discount numeric:=0;
  v_wait integer:=0;
  v_count integer;
  v_distinct integer;
  v_lines jsonb;
begin
  if lower(coalesce(auth.jwt()->>'email',''))<>'coffeebamland@gmail.com' then raise exception 'admin_only'; end if;
  if p_order_id is null or p_items is null or jsonb_typeof(p_items)<>'array'
     or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>30 then raise exception 'invalid_order_input'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) x
    where coalesce(x->>'menu_item_id','') !~* '^[0-9a-f-]{36}$'
       or coalesce(x->>'quantity','') !~ '^[0-9]+$'
       or (x->>'quantity')::integer<1 or (x->>'quantity')::integer>20) then raise exception 'invalid_order_items'; end if;
  select count(*),count(distinct (x->>'menu_item_id')::uuid) into v_count,v_distinct
  from jsonb_array_elements(p_items) x;
  if v_count<>v_distinct then raise exception 'duplicate_menu_items'; end if;

  select * into v_order from public.orders where id=p_order_id for update;
  if not found or not v_order.is_manual then raise exception 'manual_order_not_found'; end if;
  if v_order.status in ('settled','cancelled') then raise exception 'order_not_editable'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) x
    left join public.menu_items m on m.id=(x->>'menu_item_id')::uuid
    where m.id is null or not m.is_active) then raise exception 'menu_item_unavailable'; end if;

  select * into v_settings from public.cafe_settings where id=true;
  select coalesce(sum(m.price*(x->>'quantity')::integer),0),
         coalesce(sum(m.serving_minutes*(x->>'quantity')::integer),0)
    into v_subtotal,v_wait
  from jsonb_array_elements(p_items) x join public.menu_items m on m.id=(x->>'menu_item_id')::uuid;
  v_menu_discount:=round(v_subtotal*coalesce(v_settings.menu_discount_percent,0)/100);
  v_order_discount:=round(greatest(0,v_subtotal-v_menu_discount)*v_order.order_discount_percent/100);

  delete from public.order_items where order_id=p_order_id;
  insert into public.order_items(order_id,menu_item_id,item_name,unit_price,quantity,serving_minutes,line_total)
  select p_order_id,m.id,m.name,m.price,(x->>'quantity')::integer,m.serving_minutes,m.price*(x->>'quantity')::integer
  from jsonb_array_elements(p_items) x join public.menu_items m on m.id=(x->>'menu_item_id')::uuid;

  update public.orders set subtotal=v_subtotal,menu_discount_amount=v_menu_discount,
    order_discount_amount=v_order_discount,discount_amount=v_menu_discount+v_order_discount,
    total=greatest(0,v_subtotal-v_menu_discount-v_order_discount),
    estimated_wait_minutes=v_wait,updated_at=now()
  where id=p_order_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',oi.id,'menu_item_id',oi.menu_item_id,'item_name',oi.item_name,
    'unit_price',oi.unit_price,'quantity',oi.quantity,'line_total',oi.line_total
  ) order by oi.created_at),'[]'::jsonb) into v_lines
  from public.order_items oi where oi.order_id=p_order_id;
  return jsonb_build_object('order_id',p_order_id,'subtotal',v_subtotal,
    'menu_discount_amount',v_menu_discount,'order_discount_amount',v_order_discount,
    'discount_amount',v_menu_discount+v_order_discount,
    'total',greatest(0,v_subtotal-v_menu_discount-v_order_discount),'items',v_lines);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_order_discount(p_order_id uuid, p_percent numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_order public.orders%rowtype; v_discount numeric; v_total_discount numeric; v_total numeric;
begin
 if lower(coalesce(auth.jwt()->>'email',''))<>'coffeebamland@gmail.com' then raise exception 'admin_only'; end if;
 if p_percent is null or p_percent<0 or p_percent>100 then raise exception 'invalid_discount_percent'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'order_not_found'; end if;
 if v_order.status in ('settled','cancelled') then raise exception 'order_not_editable'; end if;
 v_discount:=round(greatest(0,v_order.subtotal-v_order.menu_discount_amount)*p_percent/100);
 v_total_discount:=v_order.menu_discount_amount+v_discount;
 v_total:=greatest(0,v_order.subtotal-v_total_discount);
 update public.orders set order_discount_percent=p_percent,order_discount_amount=v_discount,
   discount_amount=v_total_discount,total=v_total,updated_at=now() where id=p_order_id;
 return jsonb_build_object('order_id',p_order_id,'order_discount_percent',p_percent,
   'order_discount_amount',v_discount,'discount_amount',v_total_discount,'total',v_total);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.settle_order(p_order_id uuid, p_method text, p_customer_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
 v_order public.orders%rowtype;
 v_customer public.ledger_customers%rowtype;
 v_transaction_id uuid;
begin
 if lower(coalesce(auth.jwt()->>'email',''))<>'coffeebamland@gmail.com' then raise exception 'admin_only'; end if;
 if p_method not in ('cash','ledger') then raise exception 'invalid_settlement_method'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found then raise exception 'order_not_found'; end if;
 if v_order.status in ('settled','cancelled') then raise exception 'order_already_closed'; end if;

 if p_method='ledger' then
   if p_customer_id is null then raise exception 'ledger_customer_required'; end if;
   select * into v_customer from public.ledger_customers where id=p_customer_id and is_active for update;
   if not found then raise exception 'ledger_customer_not_found'; end if;
   if exists(select 1 from public.ledger_transactions where order_id=p_order_id and transaction_type='order_charge') then
     raise exception 'order_already_charged_to_ledger';
   end if;
   insert into public.ledger_transactions(customer_id,transaction_type,amount,order_id,description,created_by)
   values(p_customer_id,'order_charge',v_order.total,p_order_id,
     'بابت سفارش میز '||(select t.name from public.cafe_tables t where t.id=v_order.table_id),
     auth.jwt()->>'email')
   returning id into v_transaction_id;
   update public.orders set status='settled',settled_at=now(),updated_at=now(),
     settlement_method='ledger',ledger_customer_id=p_customer_id,
     ledger_customer_name=v_customer.first_name||' '||v_customer.last_name
   where id=p_order_id;
 else
   update public.orders set status='settled',settled_at=now(),updated_at=now(),
     settlement_method='cash',ledger_customer_id=null,ledger_customer_name=null
   where id=p_order_id;
 end if;
 return jsonb_build_object('order_id',p_order_id,'settlement_method',p_method,
   'ledger_customer_id',case when p_method='ledger' then p_customer_id else null end,
   'ledger_customer_name',case when p_method='ledger' then v_customer.first_name||' '||v_customer.last_name else null end,
   'amount',v_order.total,'transaction_id',v_transaction_id);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.record_ledger_payment(p_customer_id uuid, p_amount numeric, p_description text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_customer public.ledger_customers%rowtype; v_balance numeric; v_new_balance numeric; v_tx uuid;
begin
 if lower(coalesce(auth.jwt()->>'email',''))<>'coffeebamland@gmail.com' then raise exception 'admin_only'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'invalid_payment_amount'; end if;
 select * into v_customer from public.ledger_customers where id=p_customer_id for update;
 if not found then raise exception 'ledger_customer_not_found'; end if;
 select coalesce(sum(case when transaction_type='order_charge' then amount else -amount end),0)
 into v_balance from public.ledger_transactions where customer_id=p_customer_id;
 if p_amount>v_balance then raise exception 'payment_exceeds_balance'; end if;
 insert into public.ledger_transactions(customer_id,transaction_type,amount,description,created_by)
 values(p_customer_id,'payment',p_amount,coalesce(nullif(btrim(p_description),''),'پرداخت بدهی'),auth.jwt()->>'email')
 returning id into v_tx;
 v_new_balance:=v_balance-p_amount;
 return jsonb_build_object('customer_id',p_customer_id,'payment',p_amount,'balance',v_new_balance,'transaction_id',v_tx);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.delete_ledger_customer(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_balance numeric;
begin
 if lower(coalesce(auth.jwt()->>'email',''))<>'coffeebamland@gmail.com' then raise exception 'admin_only'; end if;
 perform 1 from public.ledger_customers where id=p_customer_id for update;
 if not found then raise exception 'ledger_customer_not_found'; end if;
 select coalesce(sum(case when transaction_type='order_charge' then amount else -amount end),0)
 into v_balance from public.ledger_transactions where customer_id=p_customer_id;
 if v_balance>0 then raise exception 'customer_has_outstanding_debt'; end if;
 delete from public.ledger_customers where id=p_customer_id;
 return jsonb_build_object('deleted',true,'customer_id',p_customer_id);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_admin_data_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_db_bytes bigint; v_tables jsonb; v_counts jsonb;
begin
 if lower(coalesce(auth.jwt()->>'email',''))<>'coffeebamland@gmail.com' then raise exception 'admin_only'; end if;
 select pg_database_size(current_database()) into v_db_bytes;
 select coalesce(jsonb_agg(jsonb_build_object('table_name',t.table_name,'row_count',t.row_count,
   'total_bytes',pg_total_relation_size(to_regclass('public.'||quote_ident(t.table_name)))::bigint)
   order by pg_total_relation_size(to_regclass('public.'||quote_ident(t.table_name))) desc),'[]'::jsonb)
 into v_tables
 from (values
  ('menu_categories',(select count(*) from public.menu_categories)),
  ('menu_items',(select count(*) from public.menu_items)),
  ('cafe_tables',(select count(*) from public.cafe_tables)),
  ('orders',(select count(*) from public.orders)),
  ('order_items',(select count(*) from public.order_items)),
  ('reviews',(select count(*) from public.reviews)),
  ('cafe_settings',(select count(*) from public.cafe_settings)),
  ('cafe_expenses',(select count(*) from public.cafe_expenses)),
  ('admin_data_archives',(select count(*) from public.admin_data_archives)),
  ('ledger_customers',(select count(*) from public.ledger_customers)),
  ('ledger_transactions',(select count(*) from public.ledger_transactions))
 ) as t(table_name,row_count);
 select jsonb_build_object(
  'orders',(select count(*) from public.orders),
  'open_orders',(select count(*) from public.orders where status in ('pending','accepted','preparing','ready','served')),
  'settled_orders',(select count(*) from public.orders where status='settled'),
  'cancelled_orders',(select count(*) from public.orders where status='cancelled'),
  'order_items',(select count(*) from public.order_items),
  'reviews',(select count(*) from public.reviews),
  'expenses',(select count(*) from public.cafe_expenses),
  'menu_items',(select count(*) from public.menu_items),
  'active_menu_items',(select count(*) from public.menu_items where is_active),
  'archives',(select count(*) from public.admin_data_archives),
  'ledger_customers',(select count(*) from public.ledger_customers),
  'ledger_transactions',(select count(*) from public.ledger_transactions),
  'ledger_outstanding',(select coalesce(sum(case when x.transaction_type='order_charge' then x.amount else -x.amount end),0) from public.ledger_transactions x)
 ) into v_counts;
 return jsonb_build_object('database_bytes',v_db_bytes,'database_pretty',pg_size_pretty(v_db_bytes),
   'tables',v_tables,'counts',v_counts,'measured_at',now(),
   'storage_quota_note','Storage quota and plan limits are not exposed by this database-level report.');
end;
$function$
;

revoke all on function public.save_manual_order_items(uuid,jsonb) from public,anon;

revoke all on function public.set_order_discount(uuid,numeric) from public,anon;

revoke all on function public.settle_order(uuid,text,uuid) from public,anon;

revoke all on function public.record_ledger_payment(uuid,numeric,text) from public,anon;

revoke all on function public.delete_ledger_customer(uuid) from public,anon;

grant execute on function public.save_manual_order_items(uuid,jsonb) to authenticated;

grant execute on function public.set_order_discount(uuid,numeric) to authenticated;

grant execute on function public.settle_order(uuid,text,uuid) to authenticated;

grant execute on function public.record_ledger_payment(uuid,numeric,text) to authenticated;

grant execute on function public.delete_ledger_customer(uuid) to authenticated;

grant execute on function public.create_manual_order(uuid,jsonb) to authenticated;