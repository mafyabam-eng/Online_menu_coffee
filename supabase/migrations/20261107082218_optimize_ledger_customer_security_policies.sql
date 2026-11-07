create index if not exists orders_ledger_customer_id_idx on public.orders(ledger_customer_id);

drop policy if exists "admin manages ledger transactions" on public.ledger_transactions;
create policy "admin manages ledger transactions" on public.ledger_transactions
for all to authenticated
using ((select lower(coalesce(auth.jwt()->>'email','')))='coffeebamland@gmail.com')
with check ((select lower(coalesce(auth.jwt()->>'email','')))='coffeebamland@gmail.com');

drop policy if exists "admin reads ledger customers" on public.ledger_customers;
create policy "admin reads ledger customers" on public.ledger_customers
for select to authenticated
using ((select lower(coalesce(auth.jwt()->>'email','')))='coffeebamland@gmail.com');
drop policy if exists "admin inserts ledger customers" on public.ledger_customers;
create policy "admin inserts ledger customers" on public.ledger_customers
for insert to authenticated
with check ((select lower(coalesce(auth.jwt()->>'email','')))='coffeebamland@gmail.com');
drop policy if exists "admin updates ledger customers" on public.ledger_customers;
create policy "admin updates ledger customers" on public.ledger_customers
for update to authenticated
using ((select lower(coalesce(auth.jwt()->>'email','')))='coffeebamland@gmail.com')
with check ((select lower(coalesce(auth.jwt()->>'email','')))='coffeebamland@gmail.com');
drop policy if exists "admin deletes debt-free ledger customers" on public.ledger_customers;
create policy "admin deletes debt-free ledger customers" on public.ledger_customers
for delete to authenticated
using (
 (select lower(coalesce(auth.jwt()->>'email','')))='coffeebamland@gmail.com'
 and coalesce((select sum(case when t.transaction_type='order_charge' then t.amount else -t.amount end)
   from public.ledger_transactions t where t.customer_id=ledger_customers.id),0)<=0
);
