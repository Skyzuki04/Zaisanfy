-- Prueba del modelo en 3FN
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000a801', 'vendedor.a8@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000a802', 'vendedor.b8@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000a803', 'creativo.a8@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000a804', 'cliente.a8@zaisanfy.test', now(), '{"role": "visitante", "full_name": "Cliente Ocho"}');

insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000a803', 'Estudio Ocho');

-- Vendedor A guarda una propiedad con fotos
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a801", "role": "authenticated"}', true);

do $$
declare v uuid;
begin
  v := public.save_property(null, 'Casa 3FN', null, 'venta', 'casa', 2500000, 'MXN', 3, 2, 180, 'Jalisco', 'Zapopan', null, null, null, null,
                            array['https://x.test/1.jpg', 'https://x.test/2.jpg'], 'https://x.test/360.jpg');
  if (select count(*) from public.property_photos where property_id = v) <> 3 then raise exception 'FALLA: no se guardaron las fotos'; end if;
  if (select url from public.property_photos where property_id = v and kind = 'foto' and position = 0) <> 'https://x.test/1.jpg' then
    raise exception 'FALLA: la portada no es la primera foto';
  end if;

  perform public.save_property(v, 'Casa 3FN editada', null, 'renta', 'casa', 15000, 'MXN', 3, 2, 180, 'Jalisco', 'Zapopan', null, null, null, null,
                               array['https://x.test/2.jpg'], null);
  if (select count(*) from public.property_photos where property_id = v) <> 1 then raise exception 'FALLA: al editar no se reemplazaron las fotos'; end if;

  begin
    perform public.save_property(null, 'Sin precio', null, 'venta', 'casa', 0, 'MXN', 0, 0, null, 'Jalisco', 'Zapopan', null, null, null, null, null, null);
    raise exception 'FALLA: se guardó una propiedad sin precio';
  exception when check_violation then null;
  end;
end $$;

-- Vendedor B no toca lo de A
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a802", "role": "authenticated"}', true);

do $$
declare v uuid := (select id from public.properties where title = 'Casa 3FN editada');
begin
  if v is not null then raise exception 'FALLA: B ve el borrador de A'; end if;
  reset role;
  v := (select id from public.properties where title = 'Casa 3FN editada');
  set local role authenticated;
  begin
    perform public.save_property(v, 'Robada', null, 'venta', 'casa', 1, 'MXN', 0, 0, null, 'Jalisco', 'Zapopan', null, null, null, null, null, null);
    raise exception 'FALLA: B editó la propiedad de A';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.property_photos (property_id, url, position) values (v, 'https://x.test/intruso.jpg', 9);
    raise exception 'FALLA: B agregó fotos a la propiedad de A';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Sin sesión no se ven fotos de borradores
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  if exists (select 1 from public.property_photos) then raise exception 'FALLA: sin sesión se ven fotos de un borrador'; end if;
end $$;

-- Cotización sobre una publicación: llega al creativo
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a803", "role": "authenticated"}', true);
select public.save_post(null, 'Render 3FN', null, 'render', null, null, array['https://x.test/r.jpg']);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a804", "role": "authenticated"}', true);

do $$
declare r public.contact_requests;
begin
  insert into public.contact_requests (creative_id, post_id)
  values ('00000000-0000-0000-0000-00000000a803', (select id from public.creative_posts where title = 'Render 3FN'))
  returning * into r;
  if r.creative_id is not null or r.post_id is null then raise exception 'FALLA: la cotización no quedó ligada solo a la publicación'; end if;
  if public.request_recipient(r.property_id, r.creative_id, r.post_id) <> '00000000-0000-0000-0000-00000000a803' then
    raise exception 'FALLA: la cotización no le llega al creativo';
  end if;
  begin
    insert into public.contact_requests (creative_id) values ('00000000-0000-0000-0000-00000000a803');
    raise exception 'FALLA: dos solicitudes abiertas al mismo creativo';
  exception when raise_exception then
    if sqlerrm not like '%abierta%' then raise exception 'FALLA: una abierta por creativo (%)', sqlerrm; end if;
  end;
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a803", "role": "authenticated"}', true);

do $$ begin
  if not exists (select 1 from public.my_inbox() where post_title = 'Render 3FN' and requester_name = 'Cliente Ocho') then
    raise exception 'FALLA: el creativo no ve la cotización en su bandeja';
  end if;
end $$;

reset role;
rollback;

select '3FN OK' as resultado;
