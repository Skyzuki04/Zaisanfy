-- Prueba de la compra de anuncios (ZAI-36). Resultado: COMPRA ANUNCIOS OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000a161', 'vendedor.16@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000a162', 'otro.16@zaisanfy.test',     now(), '{"role": "vendedor"}');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000016f1', '00000000-0000-0000-0000-00000000a161', 'published', 'Para anunciar', 'venta', 'casa', 100, 'Jalisco', 'Zapopan'),
  ('00000000-0000-0000-0000-0000000016f2', '00000000-0000-0000-0000-00000000a161', 'draft',     'Borrador',      'venta', 'casa', 100, 'Jalisco', 'Zapopan');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a161", "role": "authenticated"}', true);
do $$
declare hoy date := (now() at time zone 'America/Mexico_City')::date;
begin
  -- Freemium no puede anunciar
  begin
    perform public.ad_quote('00000000-0000-0000-0000-0000000016f1', hoy, hoy + 6);
    raise exception 'FALLA: Freemium pudo cotizar un anuncio';
  exception when sqlstate 'ZA003' then null;
  end;
end $$;

reset role;
set local role service_role;
select public.stripe_apply_subscription('00000000-0000-0000-0000-00000000a161', 'pro', 'sub_test16', 'activa', now(), now() + interval '1 month', false);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a161", "role": "authenticated"}', true);
do $$
declare hoy date := (now() at time zone 'America/Mexico_City')::date;
begin
  if public.ad_quote('00000000-0000-0000-0000-0000000016f1', hoy, hoy + 6) <> 7 * public.ad_price_per_day_mxn() then
    raise exception 'FALLA: el precio de 7 días no cuadra';
  end if;
  begin
    perform public.ad_quote('00000000-0000-0000-0000-0000000016f2', hoy, hoy + 6);
    raise exception 'FALLA: se cotizó un borrador';
  exception when sqlstate 'P0001' then null;
  end;
  begin
    perform public.ad_quote('00000000-0000-0000-0000-0000000016f1', hoy + 5, hoy);
    raise exception 'FALLA: aceptó fechas al revés';
  exception when sqlstate 'P0001' then null;
  end;
  begin
    perform public.ad_quote('00000000-0000-0000-0000-0000000016f1', hoy - 1, hoy);
    raise exception 'FALLA: aceptó un anuncio en el pasado';
  exception when sqlstate 'P0001' then null;
  end;
end $$;

-- El otro vendedor no puede cotizar una propiedad ajena
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a162", "role": "authenticated"}', true);
do $$ begin
  perform public.ad_quote('00000000-0000-0000-0000-0000000016f1', current_date + 1, current_date + 2);
  raise exception 'FALLA: cotizó una propiedad ajena';
exception when sqlstate 'P0001' then null;
end $$;

-- Webhook: el pago llega dos veces y solo se crea un anuncio
reset role;
set local role service_role;
select public.stripe_create_ad('00000000-0000-0000-0000-00000000a161', '00000000-0000-0000-0000-0000000016f1', 'buscador',
  (now() at time zone 'America/Mexico_City')::date, (now() at time zone 'America/Mexico_City')::date + 6, 210, 'cs_test16');
select public.stripe_create_ad('00000000-0000-0000-0000-00000000a161', '00000000-0000-0000-0000-0000000016f1', 'buscador',
  (now() at time zone 'America/Mexico_City')::date, (now() at time zone 'America/Mexico_City')::date + 6, 210, 'cs_test16');

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  if (select count(*) from public.ads where property_id = '00000000-0000-0000-0000-0000000016f1') <> 1 then
    raise exception 'FALLA: el anuncio pagado no está vigente o se duplicó';
  end if;
end $$;

reset role;
select 'COMPRA ANUNCIOS OK' as resultado;
rollback;
