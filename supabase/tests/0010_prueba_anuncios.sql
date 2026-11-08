-- Prueba de anuncios (ADS-01). Resultado: ANUNCIOS OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000aa01', 'vendedor.a10@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000aa02', 'vendedor.b10@zaisanfy.test', now(), '{"role": "vendedor"}');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000010f1', '00000000-0000-0000-0000-00000000aa01', 'published', 'Anunciada', 'venta', 'casa', 100, 'Jalisco', 'Zapopan'),
  ('00000000-0000-0000-0000-0000000010f2', '00000000-0000-0000-0000-00000000aa01', 'hidden',    'Oculta',    'venta', 'casa', 100, 'Jalisco', 'Zapopan');

insert into public.payments (id, user_id, amount_mxn, status) values
  ('00000000-0000-0000-0000-0000000010b1', '00000000-0000-0000-0000-00000000aa01', 150, 'pagado'),
  ('00000000-0000-0000-0000-0000000010b2', '00000000-0000-0000-0000-00000000aa01', 150, 'pagado'),
  ('00000000-0000-0000-0000-0000000010b3', '00000000-0000-0000-0000-00000000aa01', 150, 'pagado'),
  ('00000000-0000-0000-0000-0000000010b4', '00000000-0000-0000-0000-00000000aa01', 150, 'pendiente'),
  ('00000000-0000-0000-0000-0000000010b5', '00000000-0000-0000-0000-00000000aa01', 150, 'pagado');

-- c1 vigente · c2 empieza mañana · c3 ya terminó · c4 sin pagar · c5 propiedad oculta
insert into public.ads (id, property_id, placement, starts_on, ends_on, payment_id) values
  ('00000000-0000-0000-0000-0000000010c1', '00000000-0000-0000-0000-0000000010f1', 'buscador', current_date - 1, current_date + 7, '00000000-0000-0000-0000-0000000010b1'),
  ('00000000-0000-0000-0000-0000000010c2', '00000000-0000-0000-0000-0000000010f1', 'muro',     current_date + 2, current_date + 9, '00000000-0000-0000-0000-0000000010b2'),
  ('00000000-0000-0000-0000-0000000010c3', '00000000-0000-0000-0000-0000000010f1', 'muro',     current_date - 9, current_date - 2, '00000000-0000-0000-0000-0000000010b3'),
  ('00000000-0000-0000-0000-0000000010c4', '00000000-0000-0000-0000-0000000010f1', 'muro',     current_date - 1, current_date + 7, '00000000-0000-0000-0000-0000000010b4'),
  ('00000000-0000-0000-0000-0000000010c5', '00000000-0000-0000-0000-0000000010f2', 'buscador', current_date - 1, current_date + 7, '00000000-0000-0000-0000-0000000010b5');

-- Sin sesión: solo se ve y se registra el anuncio vigente
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  if (select count(*) from public.ads where id::text like '00000000-0000-0000-0000-0000000010c%') <> 1
     or not exists (select 1 from public.ads where id = '00000000-0000-0000-0000-0000000010c1') then
    raise exception 'FALLA: se ven anuncios fuera de fechas, sin pagar o de propiedades ocultas';
  end if;
  insert into public.ad_events (ad_id, kind) values
    ('00000000-0000-0000-0000-0000000010c1', 'impresion'),
    ('00000000-0000-0000-0000-0000000010c1', 'impresion'),
    ('00000000-0000-0000-0000-0000000010c1', 'clic');
  begin
    insert into public.ad_events (ad_id, kind) values ('00000000-0000-0000-0000-0000000010c2', 'impresion');
    raise exception 'FALLA: se registró una vista de un anuncio que aún no empieza';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.my_ad_stats();
    raise exception 'FALLA: anon pudo ver estadísticas';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Vendedor A ve las estadísticas de sus anuncios
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000aa01", "role": "authenticated"}', true);

do $$
declare
  s record;
begin
  if (select count(*) from public.my_ad_stats()) <> 5 then raise exception 'FALLA: A no ve todos sus anuncios'; end if;
  select * into s from public.my_ad_stats() where ad_id = '00000000-0000-0000-0000-0000000010c1';
  if s.impressions <> 2 or s.clicks <> 1 or not s.is_live then
    raise exception 'FALLA: las vistas y clics no cuadran (% vistas, % clics)', s.impressions, s.clicks;
  end if;
  if exists (select 1 from public.my_ad_stats() where ad_id <> '00000000-0000-0000-0000-0000000010c1' and is_live) then
    raise exception 'FALLA: un anuncio fuera de fechas, sin pagar u oculto sale como vigente';
  end if;
end $$;

-- Vendedor B no ve las de A
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000aa02", "role": "authenticated"}', true);

do $$ begin
  if exists (select 1 from public.my_ad_stats()) then raise exception 'FALLA: B ve estadísticas de A'; end if;
end $$;

reset role;
rollback;

select 'ANUNCIOS OK' as resultado;
