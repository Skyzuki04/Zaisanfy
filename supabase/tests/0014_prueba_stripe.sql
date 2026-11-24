-- Prueba de suscripciones con Stripe (ZAI-32). Resultado: STRIPE OK
-- Simula lo que hace el webhook: alta, cobro mensual (con evento repetido), cambio de plan y cancelación.
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000e141', 'vendedor.14@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000e142', 'otro.14@zaisanfy.test',     now(), '{"role": "vendedor"}');

-- El navegador no puede llamar las funciones del webhook
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e141", "role": "authenticated"}', true);
do $$ begin
  begin
    perform public.stripe_apply_subscription('00000000-0000-0000-0000-00000000e141', 'enterprise', 'sub_hack', 'activa', now(), now() + interval '1 month', false);
    raise exception 'FALLA: el navegador se puso un plan sin pagar';
  exception when insufficient_privilege then null;
  end;
  if public.my_plan() <> 'freemium' then raise exception 'FALLA: sin pagar no es Freemium'; end if;
end $$;

-- Webhook: pagó Pro
reset role;
set local role service_role;
select public.stripe_save_customer('00000000-0000-0000-0000-00000000e141', 'cus_test14');
select public.stripe_save_customer('00000000-0000-0000-0000-00000000e141', 'cus_test14');
select public.stripe_apply_subscription('00000000-0000-0000-0000-00000000e141', 'pro', 'sub_test14', 'activa',
  now(), now() + interval '1 month', false);
select public.stripe_record_invoice('sub_test14', 499, 'in_test14_1');
select public.stripe_record_invoice('sub_test14', 499, 'in_test14_1'); -- evento repetido

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e141", "role": "authenticated"}', true);
do $$
declare s record;
begin
  select * into s from public.my_subscription();
  if s.plan_id <> 'pro' or s.status <> 'activa' then raise exception 'FALLA: el plan no cambió a Pro (%)', s.plan_id; end if;
  if s.credits <> 10 then raise exception 'FALLA: créditos del mes = % (esperaba 10, sin duplicar)', s.credits; end if;
  if (select count(*) from public.payments) <> 1 then raise exception 'FALLA: el cobro repetido se guardó dos veces'; end if;
end $$;

-- El otro vendedor no ve nada de esto
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e142", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.subscriptions) or exists (select 1 from public.payments) then
    raise exception 'FALLA: un vendedor ve la suscripción o pagos de otro';
  end if;
  if public.my_plan() <> 'freemium' then raise exception 'FALLA: el otro vendedor no es Freemium'; end if;
end $$;

-- Cancela: sigue en Pro hasta que termina el periodo, luego Stripe la borra y regresa a Freemium
reset role;
set local role service_role;
select public.stripe_apply_subscription('00000000-0000-0000-0000-00000000e141', 'pro', 'sub_test14', 'activa',
  now(), now() + interval '1 month', true);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e141", "role": "authenticated"}', true);
do $$ begin
  if public.my_plan() <> 'pro' or not (select cancel_at_period_end from public.my_subscription()) then
    raise exception 'FALLA: al cancelar debe seguir en Pro hasta fin de mes';
  end if;
end $$;

reset role;
set local role service_role;
select public.stripe_apply_subscription('00000000-0000-0000-0000-00000000e141', 'pro', 'sub_test14', 'cancelada',
  now() - interval '1 month', now(), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e141", "role": "authenticated"}', true);
do $$ begin
  if public.my_plan() <> 'freemium' then raise exception 'FALLA: al terminar el periodo no regresó a Freemium'; end if;
end $$;

-- Vuelve a pagar, ahora Enterprise: queda una sola suscripción viva
reset role;
set local role service_role;
select public.stripe_apply_subscription('00000000-0000-0000-0000-00000000e141', 'enterprise', 'sub_test14_b', 'activa',
  now(), now() + interval '1 month', false);
do $$ begin
  if (select count(*) from public.subscriptions where user_id = '00000000-0000-0000-0000-00000000e141'
      and status in ('activa', 'en_prueba', 'pago_vencido')) <> 1 then
    raise exception 'FALLA: quedaron dos suscripciones vivas';
  end if;
end $$;

reset role;
select 'STRIPE OK' as resultado;
rollback;
