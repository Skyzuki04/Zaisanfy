-- Prueba de pagos
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000a901', 'vendedor.a9@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000a902', 'vendedor.b9@zaisanfy.test', now(), '{"role": "vendedor"}');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000009f1', '00000000-0000-0000-0000-00000000a901', 'published', 'Anunciada', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

-- Como el webhook de Stripe
insert into public.subscriptions (id, user_id, plan_id, status, current_period_start, current_period_end)
values ('00000000-0000-0000-0000-0000000009a1', '00000000-0000-0000-0000-00000000a901', 'pro', 'activa', now(), now() + interval '30 days');
insert into public.payments (id, user_id, amount_mxn, status) values
  ('00000000-0000-0000-0000-0000000009b1', '00000000-0000-0000-0000-00000000a901', 499, 'pagado'),
  ('00000000-0000-0000-0000-0000000009b2', '00000000-0000-0000-0000-00000000a901', 150, 'pagado');
insert into public.subscription_payments (payment_id, subscription_id) values ('00000000-0000-0000-0000-0000000009b1', '00000000-0000-0000-0000-0000000009a1');
insert into public.credit_movements (user_id, amount, reason) values ('00000000-0000-0000-0000-00000000a901', 10, 'plan');
insert into public.ads (id, property_id, placement, starts_on, ends_on, payment_id) values
  ('00000000-0000-0000-0000-0000000009c1', '00000000-0000-0000-0000-0000000009f1', 'buscador', current_date, current_date + 7, '00000000-0000-0000-0000-0000000009b2');

do $$ begin
  begin
    insert into public.subscriptions (user_id, plan_id, status) values ('00000000-0000-0000-0000-00000000a901', 'enterprise', 'activa');
    raise exception 'FALLA: dos suscripciones activas';
  exception when unique_violation then null;
  end;
end $$;

-- Vendedor A ve lo suyo
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a901", "role": "authenticated"}', true);

do $$ begin
  if public.my_plan() <> 'pro' then raise exception 'FALLA: el plan no es Pro'; end if;
  if public.my_credits() <> 10 then raise exception 'FALLA: el saldo de créditos no es 10'; end if;
  if (select count(*) from public.payments) <> 2 then raise exception 'FALLA: A no ve sus pagos'; end if;
  begin
    update public.subscriptions set plan_id = 'enterprise';
    raise exception 'FALLA: A se cambió el plan sin pagar';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.credit_movements (user_id, amount, reason) values ('00000000-0000-0000-0000-00000000a901', 1000, 'ajuste');
    raise exception 'FALLA: A se regaló créditos';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Vendedor B
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a902", "role": "authenticated"}', true);

do $$ begin
  if public.my_plan() <> 'freemium' then raise exception 'FALLA: B no quedó en Freemium'; end if;
  if exists (select 1 from public.payments) or exists (select 1 from public.subscriptions) then raise exception 'FALLA: B ve pagos de A'; end if;
  if (select count(*) from public.plans) <> 3 then raise exception 'FALLA: no se ven los 3 planes'; end if;
end $$;

-- Sin sesión
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  if not exists (select 1 from public.ads) then raise exception 'FALLA: no se ve el anuncio vigente'; end if;
  insert into public.ad_events (ad_id, kind) values ('00000000-0000-0000-0000-0000000009c1', 'impresion');
end $$;

reset role;
rollback;

select 'PAGOS OK' as resultado;
