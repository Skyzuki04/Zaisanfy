-- ZAI-32 · RF-VEN-04: suscripciones con Stripe (y los cobros de ZAI-34 y ZAI-36).
-- Las tablas ya existen desde la 0009. Aquí van las funciones que usa el webhook de Stripe
-- (supabase/functions/stripe-webhook). Solo el servidor (service_role) las puede llamar:
-- el navegador nunca escribe pagos ni planes.

-- Precios de lo que se cobra suelto (MXN). Se cambian aquí y en ningún otro lado.
create or replace function public.lead_price_mxn() returns numeric language sql immutable as $$ select 49::numeric $$;
create or replace function public.ad_price_per_day_mxn() returns numeric language sql immutable as $$ select 30::numeric $$;

-- Alta o cambio de la suscripción que manda Stripe (customer.subscription.created/updated/deleted)
create or replace function public.stripe_apply_subscription(
  p_user uuid, p_plan text, p_stripe_subscription text, p_status public.subscription_status,
  p_period_start timestamptz, p_period_end timestamptz, p_cancel_at_period_end boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from public.plans where id = p_plan) then
    raise exception 'Plan desconocido: %', p_plan;
  end if;

  update public.subscriptions
     set plan_id = p_plan, status = p_status, current_period_start = p_period_start,
         current_period_end = p_period_end, cancel_at_period_end = p_cancel_at_period_end
   where stripe_subscription_id = p_stripe_subscription
  returning id into v_id;

  if v_id is null then
    -- Si ya tenía otra viva (por ejemplo cambió de Pro a Enterprise con un checkout nuevo), la anterior se cierra
    if p_status in ('activa', 'en_prueba', 'pago_vencido') then
      update public.subscriptions set status = 'cancelada'
       where user_id = p_user and status in ('activa', 'en_prueba', 'pago_vencido');
    end if;
    insert into public.subscriptions (user_id, plan_id, status, stripe_subscription_id,
                                      current_period_start, current_period_end, cancel_at_period_end)
    values (p_user, p_plan, p_status, p_stripe_subscription, p_period_start, p_period_end, p_cancel_at_period_end)
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- Cobro mensual pagado (invoice.paid): pago + liga a la suscripción + créditos del mes. No se duplica.
create or replace function public.stripe_record_invoice(
  p_stripe_subscription text, p_amount_mxn numeric, p_payment_ref text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub     public.subscriptions;
  v_payment uuid;
  v_credits integer;
begin
  select * into v_sub from public.subscriptions where stripe_subscription_id = p_stripe_subscription;
  if v_sub.id is null then
    raise exception 'Suscripción desconocida: %', p_stripe_subscription;
  end if;
  if exists (select 1 from public.payments where stripe_payment_intent_id = p_payment_ref) then
    return; -- Stripe a veces manda el mismo evento dos veces
  end if;

  insert into public.payments (user_id, amount_mxn, status, stripe_payment_intent_id)
  values (v_sub.user_id, greatest(p_amount_mxn, 0.01), 'pagado', p_payment_ref)
  returning id into v_payment;
  insert into public.subscription_payments (payment_id, subscription_id) values (v_payment, v_sub.id);

  select monthly_credits into v_credits from public.plans where id = v_sub.plan_id;
  if v_credits > 0 then
    insert into public.credit_movements (user_id, amount, reason) values (v_sub.user_id, v_credits, 'plan');
  end if;
end;
$$;

-- Pago suelto (checkout.session.completed en modo payment). Devuelve el id del pago; si ya existía, el mismo.
create or replace function public.stripe_record_payment(p_user uuid, p_amount_mxn numeric, p_payment_ref text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.payments where stripe_payment_intent_id = p_payment_ref;
  if v_id is null then
    insert into public.payments (user_id, amount_mxn, status, stripe_payment_intent_id)
    values (p_user, p_amount_mxn, 'pagado', p_payment_ref)
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- Cliente de Stripe de cada usuario (lo crea stripe-checkout la primera vez)
create or replace function public.stripe_save_customer(p_user uuid, p_customer text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.billing_customers (user_id, stripe_customer_id) values (p_user, p_customer)
  on conflict (user_id) do nothing;
$$;

revoke execute on function public.stripe_apply_subscription, public.stripe_record_invoice,
  public.stripe_record_payment, public.stripe_save_customer from public, anon, authenticated;
grant execute on function public.stripe_apply_subscription, public.stripe_record_invoice,
  public.stripe_record_payment, public.stripe_save_customer to service_role;
grant execute on function public.lead_price_mxn, public.ad_price_per_day_mxn to anon, authenticated;

-- Para la página "Mi plan": plan vigente, cuándo se renueva o termina, y créditos
create or replace function public.my_subscription()
returns table (plan_id text, plan_name text, status public.subscription_status, current_period_end timestamptz,
               cancel_at_period_end boolean, credits integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name, s.status, s.current_period_end, coalesce(s.cancel_at_period_end, false), public.my_credits()
  from public.plans p
  left join public.subscriptions s
    on s.user_id = auth.uid() and s.plan_id = p.id and s.status in ('activa', 'en_prueba', 'pago_vencido')
  where p.id = public.my_plan();
$$;

revoke execute on function public.my_subscription from public, anon;
grant execute on function public.my_subscription to authenticated;
