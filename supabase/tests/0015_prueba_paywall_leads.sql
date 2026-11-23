-- Prueba del pay-wall y desbloqueo de leads (ZAI-33, ZAI-34) y del panel de leads del vendedor (ZAI-35).
-- Resultado: PAYWALL OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000f151', 'cliente.15@zaisanfy.test',   now(), '{"role": "visitante", "full_name": "Laura Cliente"}'),
  ('00000000-0000-0000-0000-00000000f152', 'creativo.15@zaisanfy.test',  now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000f153', 'vendedor.15a@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000f154', 'vendedor.15b@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000f155', 'creativo.15b@zaisanfy.test', now(), '{"role": "creativo"}');

insert into public.creative_profiles (id, display_name) values
  ('00000000-0000-0000-0000-00000000f152', 'Estudio 15'),
  ('00000000-0000-0000-0000-00000000f155', 'Estudio 15 B');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000015a1', '00000000-0000-0000-0000-00000000f153', 'published', 'Casa A', 'venta', 'casa', 100, 'Jalisco', 'Zapopan'),
  ('00000000-0000-0000-0000-0000000015a2', '00000000-0000-0000-0000-00000000f154', 'published', 'Casa B', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

-- El cliente pide 2 cotizaciones (a 2 creativos) y 2 visitas (a 2 vendedores)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f151", "role": "authenticated"}', true);
insert into public.contact_requests (id, creative_id, phone, message) values
  ('00000000-0000-0000-0000-0000000015c1', '00000000-0000-0000-0000-00000000f152', '3312345678', 'Quiero un render'),
  ('00000000-0000-0000-0000-0000000015c2', '00000000-0000-0000-0000-00000000f155', '3312345678', 'Quiero un plano');
insert into public.contact_requests (id, property_id, phone) values
  ('00000000-0000-0000-0000-0000000015c3', '00000000-0000-0000-0000-0000000015a1', '3312345678'),
  ('00000000-0000-0000-0000-0000000015c4', '00000000-0000-0000-0000-0000000015a2', '3312345678');

-- ZAI-33: el creativo ve la cotización con el contacto oculto, y no puede leer el teléfono directo
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f152", "role": "authenticated"}', true);
do $$
declare i record;
begin
  select * into i from public.my_inbox();
  if not i.locked or i.requester_email is not null or i.phone is not null or i.requester_name <> 'L••••••' then
    raise exception 'FALLA: la cotización bloqueada deja ver el contacto (% % %)', i.requester_name, i.requester_email, i.phone;
  end if;
  if i.message <> 'Quiero un render' then raise exception 'FALLA: el creativo no ve qué le piden'; end if;
  begin
    perform phone from public.contact_requests;
    raise exception 'FALLA: el teléfono se puede leer directo de la tabla';
  exception when insufficient_privilege then null;
  end;
  -- ZAI-34: sin créditos no se desbloquea gratis
  begin
    perform public.unlock_lead_with_credit('00000000-0000-0000-0000-0000000015c1');
    raise exception 'FALLA: desbloqueó sin créditos';
  exception when sqlstate 'ZA002' then null;
  end;
  -- Ni puede desbloquear la de otro creativo
  begin
    perform public.unlock_lead_with_credit('00000000-0000-0000-0000-0000000015c2');
    raise exception 'FALLA: desbloqueó un lead que no es suyo';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Le llegan 10 créditos de su plan Pro
reset role;
set local role service_role;
select public.stripe_apply_subscription('00000000-0000-0000-0000-00000000f152', 'pro', 'sub_test15', 'activa', now(), now() + interval '1 month', false);
select public.stripe_record_invoice('sub_test15', 499, 'in_test15_1');

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f152", "role": "authenticated"}', true);
do $$
declare i record;
begin
  if public.unlock_lead_with_credit('00000000-0000-0000-0000-0000000015c1') <> 'desbloqueada' then raise exception 'FALLA: no se desbloqueó'; end if;
  if public.unlock_lead_with_credit('00000000-0000-0000-0000-0000000015c1') <> 'ya_desbloqueada' then raise exception 'FALLA: no detectó la repetida'; end if;
  if public.my_credits() <> 9 then raise exception 'FALLA: se cobró dos veces (créditos = %)', public.my_credits(); end if;
  select * into i from public.my_inbox();
  if i.locked or i.requester_email <> 'cliente.15@zaisanfy.test' or i.phone <> '3312345678' or i.unlocked_at is null then
    raise exception 'FALLA: desbloqueada no muestra el contacto';
  end if;
  if (select count(*) from public.my_credit_history()) <> 2 then raise exception 'FALLA: el historial no tiene plan + desbloqueo'; end if;
end $$;

-- El otro creativo desbloquea pagando con Stripe (webhook repetido no cobra 2 veces)
reset role;
set local role service_role;
select public.stripe_unlock_lead('00000000-0000-0000-0000-00000000f155', '00000000-0000-0000-0000-0000000015c2', 49, 'cs_test15');
select public.stripe_unlock_lead('00000000-0000-0000-0000-00000000f155', '00000000-0000-0000-0000-0000000015c2', 49, 'cs_test15');
do $$ begin
  if (select count(*) from public.payments where stripe_payment_intent_id = 'cs_test15') <> 1 then raise exception 'FALLA: pago doble del lead'; end if;
  begin
    perform public.stripe_unlock_lead('00000000-0000-0000-0000-00000000f155', '00000000-0000-0000-0000-0000000015c1', 49, 'cs_test15_x');
    raise exception 'FALLA: el webhook desbloqueó un lead de otro';
  exception when raise_exception then null;
  end;
end $$;

-- ZAI-35: cada vendedor ve sus leads de visita completos, nunca los del otro
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f153", "role": "authenticated"}', true);
do $$
declare i record;
begin
  if (select count(*) from public.my_inbox()) <> 1 then raise exception 'FALLA: el vendedor A no ve solo su lead'; end if;
  select * into i from public.my_inbox();
  if i.property_title <> 'Casa A' or i.locked or i.requester_email is null or i.status <> 'nueva' then
    raise exception 'FALLA: el lead de visita no se ve completo y como nuevo';
  end if;
  update public.contact_requests set status = 'contactado' where id = i.id;
  if (select status from public.my_inbox()) <> 'contactado' then raise exception 'FALLA: no se marcó como visto'; end if;
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f154", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.my_inbox() where property_title = 'Casa A') then raise exception 'FALLA: B ve los leads de A'; end if;
  update public.contact_requests set status = 'cerrada' where id = '00000000-0000-0000-0000-0000000015c3';
  if exists (select 1 from public.contact_requests where id = '00000000-0000-0000-0000-0000000015c3') then
    raise exception 'FALLA: B puede ver la solicitud de A';
  end if;
end $$;

reset role;
do $$ begin
  if (select status from public.contact_requests where id = '00000000-0000-0000-0000-0000000015c3') <> 'contactado' then
    raise exception 'FALLA: B cambió el lead de A';
  end if;
end $$;

select 'PAYWALL OK' as resultado;
rollback;
