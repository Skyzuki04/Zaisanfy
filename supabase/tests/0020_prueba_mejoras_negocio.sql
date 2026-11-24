-- Prueba de mejoras de negocio (anuncios encimados y pedidos de fotógrafo vencidos). Resultado: MEJORAS OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000e201', 'vendedor.20@zaisanfy.test', now(), '{"role": "vendedor"}');
insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city, lat, lng) values
  ('00000000-0000-0000-0000-0000000020f1', '00000000-0000-0000-0000-00000000e201', 'published', 'Casa 20', 'venta', 'casa', 100, 'Jalisco', 'Zapopan', 20.7, -103.4);
insert into public.subscriptions (user_id, plan_id, status) values ('00000000-0000-0000-0000-00000000e201', 'pro', 'activa');

-- Ya tiene un anuncio pagado en el buscador del día +2 al +8
insert into public.payments (id, user_id, amount_mxn, status) values
  ('00000000-0000-0000-0000-0000000020b1', '00000000-0000-0000-0000-00000000e201', 210, 'pagado');
insert into public.ads (property_id, placement, starts_on, ends_on, payment_id) values
  ('00000000-0000-0000-0000-0000000020f1', 'buscador', current_date + 2, current_date + 8, '00000000-0000-0000-0000-0000000020b1');

-- Un pedido de fotógrafo que venció sin que nadie lo tomara
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e201", "role": "authenticated"}', true);
insert into public.service_requests (id, seller_id, property_id, scheduled_at, address, lat, lng, status)
select '00000000-0000-0000-0000-0000000020a1', '00000000-0000-0000-0000-00000000e201', '00000000-0000-0000-0000-0000000020f1',
       now() + interval '3 hours', 'Calle 20, Zapopan', 20.7, -103.4, 'pedido';
update public.service_requests set scheduled_at = now() - interval '1 day' where id = '00000000-0000-0000-0000-0000000020a1';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e201", "role": "authenticated"}', true);
do $$ begin
  begin
    perform public.ad_quote('00000000-0000-0000-0000-0000000020f1', current_date + 5, current_date + 10, 'buscador');
    raise exception 'FALLA: dejó pagar un anuncio encimado';
  exception when sqlstate 'ZA006' then null;
  end;
  -- En otro lugar o en otras fechas sí
  perform public.ad_quote('00000000-0000-0000-0000-0000000020f1', current_date + 5, current_date + 10, 'muro');
  perform public.ad_quote('00000000-0000-0000-0000-0000000020f1', current_date + 9, current_date + 12, 'buscador');

  -- El pedido vencido no bloquea uno nuevo; queda cancelado
  insert into public.service_requests (property_id, scheduled_at, address, lat, lng)
  values ('00000000-0000-0000-0000-0000000020f1', now() + interval '1 day', '', null, null);
  if (select status from public.service_requests where id = '00000000-0000-0000-0000-0000000020a1') <> 'cancelado' then
    raise exception 'FALLA: el pedido vencido no se canceló';
  end if;
end $$;

reset role;
select 'MEJORAS OK' as resultado;
rollback;
