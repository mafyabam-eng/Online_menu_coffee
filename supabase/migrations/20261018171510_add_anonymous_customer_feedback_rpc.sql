create or replace function public.submit_anonymous_customer_feedback(
 p_order_id uuid,p_session_token uuid,p_rating integer,p_message text
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
 v_order public.orders%rowtype;
 v_message text := left(trim(coalesce(p_message,'')),1200);
begin
 if p_rating is not null and (p_rating < 1 or p_rating > 5) then
  raise exception 'invalid_rating' using errcode='22023';
 end if;
 if p_rating is null and v_message = '' then
  raise exception 'empty_feedback' using errcode='22023';
 end if;
 select * into v_order from public.orders
 where id=p_order_id and customer_session_token=p_session_token;
 if not found then raise exception 'order_not_found' using errcode='42501'; end if;
 if v_order.status in ('settled','cancelled') then raise exception 'order_closed' using errcode='22023'; end if;
 if exists(select 1 from public.reviews where order_id=p_order_id) then
  raise exception 'feedback_already_submitted' using errcode='23505';
 end if;
 insert into public.reviews(order_id,rating,message) values(p_order_id,p_rating,v_message);
 return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.submit_anonymous_customer_feedback(uuid,uuid,integer,text) from public, authenticated;
grant execute on function public.submit_anonymous_customer_feedback(uuid,uuid,integer,text) to anon, service_role;
