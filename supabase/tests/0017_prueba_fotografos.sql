-- Prueba de fotógrafos bajo demanda (ZAI-39 · SRV-01). Resultado: FOTOGRAFOS OK
-- Guadalajara: el vendedor pide; un fotógrafo cercano (Zapopan) lo ve y lo acepta;
-- uno lejano (Monterrey) no lo ve; un creativo que no es fotógrafo tampoco.
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000b171', 'vendedor.17@zaisanfy.test',  now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000b172', 'foto.cerca@zaisanfy.test',   now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000b173', 'foto.lejos@zaisanfy.test',   now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000b174', 'render.17@zaisanfy.test',    now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000b175', 'foto.cerca2@zaisanfy.test',  now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000b176', 'otro.vendedor17@zaisanfy.test', now(), '{"role": "vendedor"}');

insert into public.creative_profiles (id, display_name, specialty, base_lat, base_lng, service_radius_km) values
  ('00000000-0000-0000-0000-00000000b172', 'Foto Zapopan',   'fotografia', 20.7214, -103.3918, 25),
  ('00000000-0000-0000-0000-00000000b173', 'Foto Monterrey', 'fotografia', 25.6866, -100.3161, 50),
  ('00000000-0000-0000-0000-00000000b174', 'Render GDL',     'render3d',   20.6767, -103.3475, 50),
  ('00000000-0000-0000-0000-00000000b175', 'Foto Tlaquepaque', 'fotografia', 20.6409, -103.2933, 30);

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city, neighborhood, address, lat, lng) values
  ('00000000-0000-0000-0000-0000000017f1', '00000000-0000-0000-0000-00000000b171', 'published', 'Casa Providencia', 'venta', 'casa', 100,
   'Jalisco', 'Guadalajara', 'Providencia', 'Av. Pablo Neruda 123', 20.6950, -103.3880),
  ('00000000-0000-0000-0000-0000000017f2', '00000000-0000-0000-0000-00000000b176', 'published', 'Casa ajena', 'venta', 'casa', 100,
   'Jalisco', 'Guadalajara', null, null, 20.6950, -103.3880);

-- El vendedor pide fotógrafo (la dirección y el punto salen de la propiedad)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b171", "role": "authenticated"}', true);
do $$
declare r public.service_requests;
begin
  insert into public.service_requests (id, property_id, scheduled_at, notes, address, lat, lng)
  values ('00000000-0000-0000-0000-0000000017a1', '00000000-0000-0000-0000-0000000017f1', now() + interval '1 day', 'Tocar el timbre', '', null, null)
  returning * into r;
  if r.status <> 'pedido' or r.lat is null or r.address not like 'Av. Pablo Neruda 123%' then
    raise exception 'FALLA: el pedido no tomó la ubicación de la propiedad (% %)', r.address, r.lat;
  end if;
  begin
    insert into public.service_requests (property_id, scheduled_at, address, lat, lng)
    values ('00000000-0000-0000-0000-0000000017f1', now() + interval '2 days', '', null, null);
    raise exception 'FALLA: dejó pedir dos fotógrafos para la misma propiedad';
  exception when unique_violation then null;
  end;
  begin
    insert into public.service_requests (property_id, scheduled_at, address, lat, lng)
    values ('00000000-0000-0000-0000-0000000017f2', now() + interval '1 day', '', null, null);
    raise exception 'FALLA: pidió fotógrafo para una propiedad ajena';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.service_requests set status = 'terminado' where id = '00000000-0000-0000-0000-0000000017a1';
    raise exception 'FALLA: el vendedor cambió el estado a mano';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Fotógrafo lejano y creativo de render: no lo ven
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b173", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.service_requests) or exists (select 1 from public.nearby_services() where id = '00000000-0000-0000-0000-0000000017a1') then
    raise exception 'FALLA: un fotógrafo de Monterrey ve un pedido de Guadalajara';
  end if;
  begin
    perform public.accept_service('00000000-0000-0000-0000-0000000017a1');
    raise exception 'FALLA: aceptó un pedido fuera de su zona';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b174", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.nearby_services()) then raise exception 'FALLA: un creativo que no es fotógrafo ve pedidos'; end if;
end $$;

-- Fotógrafo cercano: lo ve con la distancia y lo acepta
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b172", "role": "authenticated"}', true);
do $$
declare n record;
begin
  select * into n from public.nearby_services() where id = '00000000-0000-0000-0000-0000000017a1';
  if n.id is null or n.distance_km > 5 or n.property_title <> 'Casa Providencia' then
    raise exception 'FALLA: el fotógrafo cercano no ve el pedido (%)', n.distance_km;
  end if;
  perform public.accept_service('00000000-0000-0000-0000-0000000017a1');
end $$;

-- El segundo fotógrafo cercano llega tarde
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b175", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.nearby_services() where id = '00000000-0000-0000-0000-0000000017a1') then raise exception 'FALLA: el pedido tomado sigue saliendo libre'; end if;
  begin
    perform public.accept_service('00000000-0000-0000-0000-0000000017a1');
    raise exception 'FALLA: dos fotógrafos tomaron el mismo pedido';
  exception when sqlstate 'ZA004' then null;
  end;
  begin
    perform public.advance_service('00000000-0000-0000-0000-0000000017a1');
    raise exception 'FALLA: avanzó un pedido que no es suyo';
  exception when insufficient_privilege then null;
  end;
end $$;

-- El fotógrafo avanza: en camino → terminado
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b172", "role": "authenticated"}', true);
do $$ begin
  if public.advance_service('00000000-0000-0000-0000-0000000017a1') <> 'en_camino' then raise exception 'FALLA: no pasó a en camino'; end if;
end $$;

-- El vendedor ve el estado y quién va; ya no puede cancelar porque va en camino
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b171", "role": "authenticated"}', true);
do $$ begin
  if (select r.status::text || '|' || c.display_name from public.service_requests r
      join public.creative_profiles c on c.id = r.photographer_id where r.id = '00000000-0000-0000-0000-0000000017a1')
     <> 'en_camino|Foto Zapopan' then
    raise exception 'FALLA: el vendedor no ve el estado y el fotógrafo';
  end if;
  begin
    perform public.cancel_service('00000000-0000-0000-0000-0000000017a1');
    raise exception 'FALLA: canceló con el fotógrafo en camino';
  exception when sqlstate 'P0001' then null;
  end;
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b172", "role": "authenticated"}', true);
do $$ begin
  if public.advance_service('00000000-0000-0000-0000-0000000017a1') <> 'terminado' then raise exception 'FALLA: no se terminó'; end if;
  begin
    perform public.advance_service('00000000-0000-0000-0000-0000000017a1');
    raise exception 'FALLA: avanzó un pedido terminado';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Ya terminado, el vendedor puede pedir otro para la misma propiedad, y cancelarlo
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b171", "role": "authenticated"}', true);
do $$ begin
  insert into public.service_requests (id, property_id, scheduled_at, address, lat, lng)
  values ('00000000-0000-0000-0000-0000000017a2', '00000000-0000-0000-0000-0000000017f1', now() + interval '3 days', '', null, null);
  perform public.cancel_service('00000000-0000-0000-0000-0000000017a2');
  if (select status from public.service_requests where id = '00000000-0000-0000-0000-0000000017a2') <> 'cancelado' then
    raise exception 'FALLA: no se canceló';
  end if;
end $$;

-- Sin sesión no se ve nada
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  perform 1 from public.service_requests;
  raise exception 'FALLA: sin sesión se ven pedidos';
exception when insufficient_privilege then null;
end $$;

reset role;
select 'FOTOGRAFOS OK' as resultado;
rollback;
