-- Prevent deleting a ledger account while any balance is outstanding.
drop policy if exists "admin manages ledger customers" on public.ledger_customers;
drop policy if exists "admin reads ledger customers" on public.ledger_customers;
drop policy if exists "admin inserts ledger customers" on public.ledger_customers;
drop policy if exists "admin updates ledger customers" on public.ledger_customers;
drop policy if exists "admin deletes debt-free ledger customers" on public.ledger_customers;
create policy "admin reads ledger customers" on public.ledger_customers
 for select to authenticated using (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com');
create policy "admin inserts ledger customers" on public.ledger_customers
 for insert to authenticated with check (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com');
create policy "admin updates ledger customers" on public.ledger_customers
 for update to authenticated
 using (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com')
 with check (lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com');
create policy "admin deletes debt-free ledger customers" on public.ledger_customers
 for delete to authenticated
 using (
  lower(coalesce(auth.jwt()->>'email',''))='coffeebamland@gmail.com'
  and coalesce((select sum(case when t.transaction_type='order_charge' then t.amount else -t.amount end)
    from public.ledger_transactions t where t.customer_id=ledger_customers.id),0)<=0
 );