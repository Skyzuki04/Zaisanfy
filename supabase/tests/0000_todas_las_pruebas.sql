-- Todas las pruebas (0002 a 0022). Cada una hace ROLLBACK y no deja datos.
-- Al final debe decir TODAS LAS PRUEBAS OK. Si algo falla, el error empieza con FALLA:

-- 0002_prueba_permisos.sql
-- Prueba de permisos. Resultado: ZAI-20 OK
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'vendedora.a@zaisanfy.test', '{"role": "vendedor", "full_name": "Vendedora A"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'vendedor.b@zaisanfy.test',  '{"role": "vendedor", "full_name": "Vendedor B"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'visitante@zaisanfy.test',   '{"role": "admin"}');  -- pide admin a propósito

insert into public.properties (seller_id, status, title, operation, property_type, price, state, city)
select s.id, st.status::public.property_status, 'Prueba ' || st.status || ' ' || s.tag, 'venta', 'casa', 1000000, 'Jalisco', 'Zapopan'
from (values ('00000000-0000-0000-0000-0000000000a1'::uuid, 'A'),
             ('00000000-0000-0000-0000-0000000000b2'::uuid, 'B')) as s(id, tag),
     (values ('published'), ('draft')) as st(status);

do $$ begin
  if (select role from public.profiles where id = '00000000-0000-0000-0000-0000000000a1') <> 'vendedor' then
    raise exception 'FALLA: el perfil de A no quedó como vendedor';
  end if;
  if (select role from public.profiles where id = '00000000-0000-0000-0000-0000000000c3') <> 'visitante' then
    raise exception 'FALLA: alguien pudo registrarse como admin';
  end if;
end $$;

-- Visitante sin sesión (anon)
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  if exists (select 1 from public.properties where status <> 'published') then
    raise exception 'FALLA: sin sesión se ven propiedades no publicadas';
  end if;
  if not exists (select 1 from public.properties where title = 'Prueba published A') then
    raise exception 'FALLA: sin sesión no se ven las publicadas';
  end if;
  begin
    insert into public.properties (seller_id, title, operation, property_type, price, state, city)
    values ('00000000-0000-0000-0000-0000000000a1', 'Intruso', 'venta', 'casa', 1, 'Puebla', 'Puebla');
    raise exception 'FALLA: sin sesión se pudo crear una propiedad';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Vendedora A
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);

do $$
declare n int;
begin
  if not exists (select 1 from public.properties where title = 'Prueba draft A') then
    raise exception 'FALLA: A no ve su propio borrador';
  end if;
  if exists (select 1 from public.properties where title = 'Prueba draft B') then
    raise exception 'FALLA: A ve el borrador de B';
  end if;

  update public.properties set status = 'hidden' where title = 'Prueba published B';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: A pudo editar una propiedad de B'; end if;

  delete from public.properties where title = 'Prueba published B';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: A pudo borrar una propiedad de B'; end if;

  update public.properties set status = 'published' where title = 'Prueba draft A';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: A no pudo publicar su propia propiedad'; end if;

  begin
    update public.properties set seller_id = '00000000-0000-0000-0000-0000000000b2' where title = 'Prueba published A';
    raise exception 'FALLA: A pudo pasarle su propiedad a B';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.properties (seller_id, title, operation, property_type, price, state, city)
    values ('00000000-0000-0000-0000-0000000000b2', 'A nombre de B', 'venta', 'casa', 1, 'Puebla', 'Puebla');
    raise exception 'FALLA: A pudo crear una propiedad a nombre de B';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000a1';
    raise exception 'FALLA: A pudo cambiarse el rol a admin';
  exception when insufficient_privilege then null;
  end;

  update public.profiles set full_name = 'Vendedora A (editado)' where id = '00000000-0000-0000-0000-0000000000a1';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: A no pudo editar su nombre'; end if;

  if (select count(*) from public.profiles) <> 1 then
    raise exception 'FALLA: A ve perfiles de otras personas';
  end if;
end $$;

-- Visitante con sesión
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000c3", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.properties (seller_id, title, operation, property_type, price, state, city)
    values ('00000000-0000-0000-0000-0000000000c3', 'No soy vendedor', 'venta', 'casa', 1, 'Puebla', 'Puebla');
    raise exception 'FALLA: un visitante pudo crear una propiedad';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from public.properties where status <> 'published') then
    raise exception 'FALLA: un visitante ve propiedades no publicadas';
  end if;
end $$;

reset role;
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000c3';
set local role authenticated;

do $$ begin
  if not exists (select 1 from public.properties where title = 'Prueba draft B') then
    raise exception 'FALLA: el admin no ve los borradores';
  end if;
  if (select count(*) from public.profiles) < 3 then
    raise exception 'FALLA: el admin no ve todos los perfiles';
  end if;
end $$;

reset role;
rollback;

select 'ZAI-20 OK' as resultado;

-- 0003_prueba_perfiles.sql
-- Prueba de perfiles de creativos
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000c001', 'creativa.a@zaisanfy.test', '{"role": "creativo", "full_name": "Creativa A"}'),
  ('00000000-0000-0000-0000-00000000c002', 'creativo.b@zaisanfy.test', '{"role": "creativo", "full_name": "Creativo B"}'),
  ('00000000-0000-0000-0000-00000000c003', 'vendedor.c@zaisanfy.test', '{"role": "vendedor", "full_name": "Vendedor C"}');

-- Creativa A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c001", "role": "authenticated"}', true);

do $$
declare n int;
begin
  insert into public.creative_profiles (id, display_name, specialty, city)
  values ('00000000-0000-0000-0000-00000000c001', 'Estudio A', 'render3d', 'Zapopan');

  begin
    insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c002', 'Perfil ajeno');
    raise exception 'FALLA: A pudo crear el perfil de B';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Creativo B
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c002", "role": "authenticated"}', true);

do $$
declare n int;
begin
  insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c002', 'Estudio B');

  update public.creative_profiles set bio = 'hackeado' where id = '00000000-0000-0000-0000-00000000c001';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: B editó el perfil de A'; end if;

  update public.creative_profiles set bio = 'Renders para desarrolladores' where id = '00000000-0000-0000-0000-00000000c002';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: B no pudo editar su propio perfil'; end if;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c003", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c003', 'No soy creativo');
    raise exception 'FALLA: un vendedor creó un perfil de creativo';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$
declare n int;
begin
  if (select count(*) from public.creative_profiles where id in ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000c002')) <> 2 then
    raise exception 'FALLA: sin sesión no se ven los perfiles públicos';
  end if;
  update public.creative_profiles set bio = 'hackeado';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: sin sesión se editó un perfil'; end if;
end $$;

reset role;
rollback;

select 'ZAI-27 OK' as resultado;

-- 0004_prueba_portafolio.sql
-- Prueba del portafolio
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000c001', 'creativa.a@zaisanfy.test', '{"role": "creativo", "full_name": "Creativa A"}'),
  ('00000000-0000-0000-0000-00000000c002', 'creativo.b@zaisanfy.test', '{"role": "creativo", "full_name": "Creativo B"}'),
  ('00000000-0000-0000-0000-00000000c003', 'vendedor.c@zaisanfy.test', '{"role": "vendedor", "full_name": "Vendedor C"}');

-- Creativa A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c001", "role": "authenticated"}', true);

do $$
declare n int;
begin
  insert into public.creative_profiles (id, display_name, specialty, city)
  values ('00000000-0000-0000-0000-00000000c001', 'Estudio A', 'render3d', 'Zapopan');

  begin
    insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c002', 'Perfil ajeno');
    raise exception 'FALLA: A pudo crear el perfil de B';
  exception when insufficient_privilege then null;
  end;

  perform public.save_post(null, 'Render de sala', null, 'render', 'casa', 'Zapopan',
                           array['https://res.cloudinary.com/x/image/upload/a.jpg', 'https://res.cloudinary.com/x/image/upload/a2.jpg']);
  if (select count(*) from public.post_images i join public.creative_posts p on p.id = i.post_id where p.title = 'Render de sala') <> 2 then
    raise exception 'FALLA: no se guardaron las imágenes en orden';
  end if;

  begin
    perform public.save_post(null, 'Sin imágenes', null, 'idea', null, null, array[]::text[]);
    raise exception 'FALLA: se guardó una publicación sin imágenes';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
end $$;

-- Creativo B
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c002", "role": "authenticated"}', true);

do $$
declare n int;
begin
  insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c002', 'Estudio B');

  update public.creative_profiles set bio = 'hackeado' where id = '00000000-0000-0000-0000-00000000c001';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: B editó el perfil de A'; end if;

  update public.creative_posts set title = 'hackeado' where creative_id = '00000000-0000-0000-0000-00000000c001';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: B editó el portafolio de A'; end if;

  delete from public.creative_posts where creative_id = '00000000-0000-0000-0000-00000000c001';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: B borró el portafolio de A'; end if;

  begin
    insert into public.creative_posts (creative_id, title, category)
    values ('00000000-0000-0000-0000-00000000c001', 'A nombre de A', 'idea');
    raise exception 'FALLA: B publicó en el portafolio de A';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.post_images (post_id, url, position)
    select id, 'https://res.cloudinary.com/x/image/upload/intruso.jpg', 5 from public.creative_posts where title = 'Render de sala';
    raise exception 'FALLA: B agregó imágenes al portafolio de A';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c003", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c003', 'No soy creativo');
    raise exception 'FALLA: un vendedor creó un perfil de creativo';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$
declare n int;
begin
  if (select count(*) from public.creative_profiles where id in ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000c002')) <> 2 then
    raise exception 'FALLA: sin sesión no se ven los perfiles públicos';
  end if;
  if not exists (select 1 from public.creative_posts where title = 'Render de sala') then
    raise exception 'FALLA: sin sesión no se ve el portafolio';
  end if;
  begin
    update public.creative_posts set title = 'hackeado' where title = 'Render de sala';
    get diagnostics n = row_count;
    if n > 0 then raise exception 'FALLA: sin sesión se editó un portafolio'; end if;
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;

select 'ZAI-28 OK' as resultado;

-- 0005_prueba_mi_lista.sql
-- Prueba de Mi Lista
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d001', 'visitante.a@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d002', 'visitante.b@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d003', 'vendedor.d@zaisanfy.test', '{"role": "vendedor"}');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000d003', 'published',
   'Publicada de prueba', 'venta', 'casa', 100, 'Jalisco', 'Zapopan'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-00000000d003', 'draft',
   'Borrador de prueba', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

-- Visitante A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d001", "role": "authenticated"}', true);

do $$
declare n int;
begin
  insert into public.bookmarks (property_id) values ('00000000-0000-0000-0000-0000000000f1');
  if (select count(*) from public.bookmarks) <> 1 then raise exception 'FALLA: A no ve su lista'; end if;

  begin
    insert into public.bookmarks (property_id) values ('00000000-0000-0000-0000-0000000000f1');
    raise exception 'FALLA: se guardó dos veces la misma propiedad';
  exception when unique_violation then null;
  end;

  begin
    insert into public.bookmarks (property_id) values ('00000000-0000-0000-0000-0000000000f2');
    raise exception 'FALLA: se guardó una propiedad no publicada';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.bookmarks (user_id, property_id) values ('00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000000f1');
    raise exception 'FALLA: A guardó en la lista de B';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Visitante B
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d002", "role": "authenticated"}', true);

do $$
declare n int;
begin
  if exists (select 1 from public.bookmarks) then raise exception 'FALLA: B ve la lista de A'; end if;
  delete from public.bookmarks where property_id = '00000000-0000-0000-0000-0000000000f1';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: B borró de la lista de A'; end if;
end $$;

-- A quita de su lista
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d001", "role": "authenticated"}', true);

do $$
declare n int;
begin
  delete from public.bookmarks where property_id = '00000000-0000-0000-0000-0000000000f1';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: A no pudo quitar de su lista'; end if;
end $$;

-- Sin sesión no hay lista
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  if exists (select 1 from public.bookmarks) then raise exception 'FALLA: sin sesión se ven listas'; end if;
  begin
    insert into public.bookmarks (user_id, property_id) values ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000000f1');
    raise exception 'FALLA: sin sesión se pudo guardar en una lista';
  exception when insufficient_privilege or not_null_violation then null;
  end;
end $$;

reset role;
rollback;

select 'ZAI-31 OK' as resultado;

-- 0006_prueba_solicitudes.sql
-- Prueba de solicitudes. Resultado: ZAI-33 OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000e001', 'cliente.a@zaisanfy.test', now(), '{"role": "visitante", "full_name": "Cliente A"}'),
  ('00000000-0000-0000-0000-00000000e002', 'cliente.b@zaisanfy.test', now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000e003', 'vendedor.e@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000e004', 'creativo.e@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000e005', 'sin.confirmar@zaisanfy.test', null, '{"role": "visitante"}');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000001f1', '00000000-0000-0000-0000-00000000e003', 'published',
   'Publicada de prueba', 'venta', 'casa', 100, 'Jalisco', 'Zapopan'),
  ('00000000-0000-0000-0000-0000000001f2', '00000000-0000-0000-0000-00000000e003', 'draft',
   'Borrador de prueba', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

insert into public.creative_profiles (id, display_name, specialty) values
  ('00000000-0000-0000-0000-00000000e004', 'Estudio de prueba', 'interiorismo');

-- Cliente A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e001", "role": "authenticated"}', true);

do $$
declare r public.contact_requests;
begin
  insert into public.contact_requests (property_id, requester_id, message)
  values ('00000000-0000-0000-0000-0000000001f1', '00000000-0000-0000-0000-00000000e002', 'Me interesa')
  returning id, property_id, creative_id, post_id, requester_id into r.id, r.property_id, r.creative_id, r.post_id, r.requester_id; -- el teléfono no se lee (0015)
  if public.request_recipient(r.property_id, r.creative_id, r.post_id) <> '00000000-0000-0000-0000-00000000e003' then raise exception 'FALLA: el destinatario no es el vendedor'; end if;
  if r.requester_id <> '00000000-0000-0000-0000-00000000e001' then raise exception 'FALLA: se mandó a nombre de otro'; end if;
  if public.kind(r) <> 'visita' then raise exception 'FALLA: el tipo no es visita'; end if;
  if exists (select 1 from public.my_inbox()) then raise exception 'FALLA: el cliente ve la bandeja del vendedor'; end if;

  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: dos solicitudes abiertas para la misma propiedad';
  exception when raise_exception then
    if sqlerrm not like '%abierta%' then raise exception 'FALLA: una abierta por propiedad (%)', sqlerrm; end if;
  end;

  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f2');
    raise exception 'FALLA: se pidió visita a una propiedad no publicada';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;

  insert into public.contact_requests (creative_id, message) values ('00000000-0000-0000-0000-00000000e004', 'Cotización');
  if (select count(*) from public.contact_requests) <> 2 then raise exception 'FALLA: A no ve sus solicitudes'; end if;

  -- el cliente no puede cambiar el estado
  update public.contact_requests set status = 'cerrada';
  if exists (select 1 from public.contact_requests where status <> 'nueva') then raise exception 'FALLA: el cliente cambió el estado'; end if;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);

do $$
declare i int;
begin
  if exists (select 1 from public.contact_requests) then raise exception 'FALLA: B ve solicitudes de A'; end if;
end $$;

do $$ begin
  for i in 1..5 loop
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e003", "role": "authenticated"}', true);
    update public.contact_requests set status = 'cerrada' where requester_id = '00000000-0000-0000-0000-00000000e002';
  end loop;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);
end $$;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.contact_requests (creative_id) values ('00000000-0000-0000-0000-00000000e004');
    raise exception 'FALLA: no se aplicó el límite de 5 por día';
  exception when raise_exception then
    if sqlerrm not like '%límite%' then raise exception 'FALLA: límite de 5 por día (%)', sqlerrm; end if;
  end;
end $$;

-- El vendedor ve y atiende solo lo suyo
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e003", "role": "authenticated"}', true);

do $$
declare n int;
begin
  if exists (select 1 from public.contact_requests where property_id is null) then raise exception 'FALLA: el vendedor ve cotizaciones del creativo'; end if;
  if not exists (select 1 from public.my_inbox() where requester_name = 'Cliente A' and requester_email = 'cliente.a@zaisanfy.test' and property_title = 'Publicada de prueba') then
    raise exception 'FALLA: la bandeja no muestra los datos del cliente';
  end if;
  update public.contact_requests set status = 'contactado' where requester_id = '00000000-0000-0000-0000-00000000e001';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: el vendedor no pudo cambiar el estado'; end if;

  begin
    update public.contact_requests set message = 'cambiado' where requester_id = '00000000-0000-0000-0000-00000000e001';
    raise exception 'FALLA: el vendedor cambió el mensaje del cliente';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: el vendedor se contactó a sí mismo';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
end $$;

-- El creativo ve su cotización
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e004", "role": "authenticated"}', true);

do $$ begin
  if (select count(*) from public.contact_requests) <> 1 then raise exception 'FALLA: el creativo no ve solo su cotización'; end if;
  if (select count(*) from public.my_inbox() where kind = 'cotizacion') <> 1 then raise exception 'FALLA: la cotización no llega a la bandeja del creativo'; end if;
end $$;

-- Correo sin confirmar
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e005", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: se aceptó una solicitud con el correo sin confirmar';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
end $$;

-- Sin sesión no hay nada
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  begin
    if exists (select 1 from public.contact_requests) then raise exception 'FALLA: sin sesión se ven solicitudes'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: sin sesión se pudo enviar una solicitud';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;

select 'ZAI-33 OK' as resultado;

-- 0007_prueba_mejora_de_cuenta.sql
-- Prueba de mejora de cuenta
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000f001', 'cliente.f@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000f002', 'cliente.g@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000f003', 'vendedor.f@zaisanfy.test', '{"role": "vendedor"}');

-- Cliente F se vuelve vendedor
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f001", "role": "authenticated"}', true);

do $$ begin
  begin
    perform public.upgrade_role('admin');
    raise exception 'FALLA: un cliente se hizo admin';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;

  if public.upgrade_role('vendedor') <> 'vendedor' then raise exception 'FALLA: no se volvió vendedor'; end if;
  if (select role from public.profiles where id = auth.uid()) <> 'vendedor' then raise exception 'FALLA: el perfil no cambió'; end if;

  begin
    perform public.upgrade_role('creativo');
    raise exception 'FALLA: un vendedor cambió a creativo';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
  begin
    perform public.upgrade_role('visitante');
    raise exception 'FALLA: se pudo bajar a visitante';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;

  begin
    update public.profiles set role = 'admin' where id = auth.uid();
    raise exception 'FALLA: se editó el rol sin el RPC';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f002", "role": "authenticated"}', true);

do $$ begin
  if public.upgrade_role('creativo') <> 'creativo' then raise exception 'FALLA: no se volvió creativo'; end if;
end $$;

reset role;
do $$ begin
  if (select role from public.profiles where id = '00000000-0000-0000-0000-00000000f003') <> 'vendedor' then raise exception 'FALLA: cambió el rol de otro usuario'; end if;
end $$;

-- Sin sesión no se puede
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  begin
    perform public.upgrade_role('vendedor');
    raise exception 'FALLA: sin sesión se pudo cambiar de rol';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;

select 'MEJORA DE CUENTA OK' as resultado;

-- 0008_prueba_3fn.sql
-- Prueba del modelo en 3FN
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000a801', 'vendedor.a8@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000a802', 'vendedor.b8@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000a803', 'creativo.a8@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000a804', 'cliente.a8@zaisanfy.test', now(), '{"role": "visitante", "full_name": "Cliente Ocho"}');

insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000a803', 'Estudio Ocho');

-- Vendedor A guarda con fotos
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

-- Sin sesión
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  if exists (select 1 from public.property_photos where url like 'https://x.test/%') then raise exception 'FALLA: sin sesión se ven fotos de un borrador'; end if;
end $$;

-- Cotización sobre una publicación
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
  returning id, property_id, creative_id, post_id, requester_id into r.id, r.property_id, r.creative_id, r.post_id, r.requester_id; -- el teléfono no se lee (0015)
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
  if not exists (select 1 from public.my_inbox() where post_title = 'Render 3FN' and requester_name = 'C••••••' and requester_email is null and locked) then -- pay-wall (0015)
    raise exception 'FALLA: el creativo no ve la cotización en su bandeja';
  end if;
end $$;

reset role;
rollback;

select '3FN OK' as resultado;

-- 0009_prueba_pagos.sql
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
  ('00000000-0000-0000-0000-0000000009c1', '00000000-0000-0000-0000-0000000009f1', 'buscador', current_date - 1, current_date + 7, '00000000-0000-0000-0000-0000000009b2');

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

-- 0010_prueba_anuncios.sql
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

-- 0012_prueba_isocronas.sql
-- Prueba de búsqueda por isocronas (ZAI-38 · GEO-01). Resultado: ISOCRONAS OK
-- 3 puntos en ciudades distintas (CDMX, Guadalajara, Monterrey). En cada una hay una casa dentro
-- de la zona y otra fuera. La zona es un polígono como el que regresa Mapbox.
-- Solo se cuentan las propiedades de esta prueba, para que no estorben las que ya hay en la base.
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000ab01', 'vendedor.a12@zaisanfy.test', '{"role": "vendedor"}');

-- Plan Enterprise: publica sin límite (0013)
insert into public.subscriptions (user_id, plan_id, status) values ('00000000-0000-0000-0000-00000000ab01', 'enterprise', 'activa');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city, lat, lng) values
  -- CDMX: zona alrededor del Zócalo (19.4326, -99.1332)
  ('00000000-0000-0000-0000-0000000012a1', '00000000-0000-0000-0000-00000000ab01', 'published', 'CDMX dentro',   'venta', 'casa', 100, 'CDMX', 'Cuauhtémoc', 19.4300, -99.1400),
  ('00000000-0000-0000-0000-0000000012a2', '00000000-0000-0000-0000-00000000ab01', 'published', 'CDMX fuera',    'venta', 'casa', 100, 'CDMX', 'Tlalpan',    19.2900, -99.1700),
  ('00000000-0000-0000-0000-0000000012a3', '00000000-0000-0000-0000-00000000ab01', 'draft',     'CDMX borrador', 'venta', 'casa', 100, 'CDMX', 'Cuauhtémoc', 19.4330, -99.1330),
  -- Guadalajara: zona alrededor del centro (20.6767, -103.3475)
  ('00000000-0000-0000-0000-0000000012b1', '00000000-0000-0000-0000-00000000ab01', 'published', 'GDL dentro',    'venta', 'casa', 100, 'Jalisco', 'Guadalajara', 20.6800, -103.3500),
  ('00000000-0000-0000-0000-0000000012b2', '00000000-0000-0000-0000-00000000ab01', 'published', 'GDL fuera',     'venta', 'casa', 100, 'Jalisco', 'Tlajomulco',  20.4700, -103.4400),
  -- Monterrey: zona alrededor de la Macroplaza (25.6694, -100.3097)
  ('00000000-0000-0000-0000-0000000012c1', '00000000-0000-0000-0000-00000000ab01', 'published', 'MTY dentro',    'venta', 'casa', 100, 'Nuevo León', 'Monterrey', 25.6700, -100.3100),
  ('00000000-0000-0000-0000-0000000012c2', '00000000-0000-0000-0000-00000000ab01', 'published', 'MTY fuera',     'venta', 'casa', 100, 'Nuevo León', 'Apodaca',   25.7800, -100.1900),
  -- Sin coordenadas: nunca entra en una zona
  ('00000000-0000-0000-0000-0000000012d1', '00000000-0000-0000-0000-00000000ab01', 'published', 'Sin ubicación', 'venta', 'casa', 100, 'CDMX', 'Cuauhtémoc', null, null);

do $$ begin
  if (select geom is null from public.properties where id = '00000000-0000-0000-0000-0000000012a1') then
    raise exception 'FALLA: no se calculó el punto (geom) a partir de lat y lng';
  end if;
  if (select geom is not null from public.properties where id = '00000000-0000-0000-0000-0000000012d1') then
    raise exception 'FALLA: una propiedad sin lat/lng tiene punto';
  end if;
end $$;

-- Visitante sin sesión (como el Escaparate)
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$
declare
  cdmx jsonb := '{"type":"Polygon","coordinates":[[[-99.17,19.40],[-99.10,19.40],[-99.10,19.46],[-99.17,19.46],[-99.17,19.40]]]}';
  gdl  jsonb := '{"type":"Polygon","coordinates":[[[-103.38,20.65],[-103.31,20.65],[-103.31,20.71],[-103.38,20.71],[-103.38,20.65]]]}';
  mty  jsonb := '{"type":"Polygon","coordinates":[[[-100.34,25.64],[-100.28,25.64],[-100.28,25.70],[-100.34,25.70],[-100.34,25.64]]]}';
  ids text[];
begin
  select array_agg(title order by title) into ids from public.properties_in_zone(cdmx) where seller_id = '00000000-0000-0000-0000-00000000ab01';
  if ids is distinct from array['CDMX dentro'] then raise exception 'FALLA: CDMX regresó %', ids; end if;

  select array_agg(title order by title) into ids from public.properties_in_zone(gdl) where seller_id = '00000000-0000-0000-0000-00000000ab01';
  if ids is distinct from array['GDL dentro'] then raise exception 'FALLA: Guadalajara regresó %', ids; end if;

  select array_agg(title order by title) into ids from public.properties_in_zone(mty) where seller_id = '00000000-0000-0000-0000-00000000ab01';
  if ids is distinct from array['MTY dentro'] then raise exception 'FALLA: Monterrey regresó %', ids; end if;

  -- Una zona con dos partes (MultiPolygon), como cuando la isocrona cruza un río o una sierra
  select array_agg(title order by title) into ids from public.properties_in_zone(jsonb_build_object(
    'type', 'MultiPolygon', 'coordinates', jsonb_build_array(cdmx->'coordinates', mty->'coordinates'))) where seller_id = '00000000-0000-0000-0000-00000000ab01';
  if ids is distinct from array['CDMX dentro', 'MTY dentro'] then raise exception 'FALLA: MultiPolygon regresó %', ids; end if;

  -- Algo que no es una zona no regresa nada (ni truena)
  if exists (select 1 from public.properties_in_zone('{"type":"Point","coordinates":[-99.13,19.43]}')) then
    raise exception 'FALLA: un punto se trató como zona';
  end if;
  if exists (select 1 from public.properties_in_zone('"hola"')) then
    raise exception 'FALLA: un texto se trató como zona';
  end if;
end $$;

reset role;
rollback;

select 'ISOCRONAS OK' as resultado;

-- 0013_prueba_limite_publicaciones.sql
-- Prueba del límite WIP por plan. Resultado: LIMITE WIP OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d301', 'freemium.13@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000d302', 'pro.13@zaisanfy.test',      now(), '{"role": "vendedor"}');

insert into public.subscriptions (user_id, plan_id, status, current_period_start, current_period_end) values
  ('00000000-0000-0000-0000-00000000d302', 'pro', 'activa', now() - interval '1 day', now() + interval '29 days');

-- 4 borradores de cada vendedor
insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city)
select ('00000000-0000-0000-0000-0000000013' || u || n)::uuid,
       ('00000000-0000-0000-0000-00000000d30' || u)::uuid,
       'draft', 'Casa ' || n, 'venta', 'casa', 100, 'Jalisco', 'Zapopan'
from generate_series(1, 2) u, generate_series(1, 4) n;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d301", "role": "authenticated"}', true);

do $$
declare q record;
begin
  -- Freemium publica 3 sin problema
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001311';
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001312';
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001313';

  -- La cuarta se bloquea con el código ZA001
  begin
    update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001314';
    raise exception 'FALLA: Freemium publicó una cuarta propiedad';
  exception when sqlstate 'ZA001' then null;
  end;

  -- Editar una que ya está publicada sí se puede
  update public.properties set title = 'Casa 1 editada' where id = '00000000-0000-0000-0000-000000001311';

  -- Si oculta una, ya puede publicar la cuarta
  update public.properties set status = 'hidden' where id = '00000000-0000-0000-0000-000000001311';
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001314';

  select * into q from public.my_publish_quota();
  if q.plan_id <> 'freemium' or q.max_published <> 3 or q.published <> 3 then
    raise exception 'FALLA: my_publish_quota dice % % %', q.plan_id, q.max_published, q.published;
  end if;
end $$;

-- Pro publica las 4
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d302", "role": "authenticated"}', true);
do $$
begin
  update public.properties set status = 'published' where seller_id = '00000000-0000-0000-0000-00000000d302';
  if (select count(*) from public.properties where seller_id = '00000000-0000-0000-0000-00000000d302' and status = 'published') <> 4 then
    raise exception 'FALLA: Pro no pudo publicar 4';
  end if;
  if (select published from public.my_publish_quota()) <> 4 then
    raise exception 'FALLA: my_publish_quota no cuenta las de Pro';
  end if;
end $$;

-- Nadie de fuera puede preguntar el plan de otro
do $$
begin
  perform public.plan_of('00000000-0000-0000-0000-00000000d302');
  raise exception 'FALLA: plan_of se puede llamar desde la app';
exception when insufficient_privilege then null;
end $$;

select 'LIMITE WIP OK' as resultado;
rollback;

-- 0014_prueba_stripe.sql
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

-- 0015_prueba_paywall_leads.sql
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

-- 0016_prueba_compra_anuncios.sql
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

-- 0017_prueba_fotografos.sql
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
  if exists (select 1 from public.service_requests) or exists (select 1 from public.nearby_services()) then
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
  select * into n from public.nearby_services();
  if n.id is null or n.distance_km > 5 or n.property_title <> 'Casa Providencia' then
    raise exception 'FALLA: el fotógrafo cercano no ve el pedido (%)', n.distance_km;
  end if;
  perform public.accept_service('00000000-0000-0000-0000-0000000017a1');
end $$;

-- El segundo fotógrafo cercano llega tarde
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000b175", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.nearby_services()) then raise exception 'FALLA: el pedido tomado sigue saliendo libre'; end if;
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

-- 0018_prueba_reportes.sql
-- Prueba de reportes (ZAI-33, antitrolls). Resultado: REPORTES OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000c181', 'cliente.18@zaisanfy.test',  now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000c182', 'vendedor.18@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000c183', 'creativo.18@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000c184', 'admin.18@zaisanfy.test',    now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000c185', 'sinconfirmar.18@zaisanfy.test', null, '{"role": "visitante"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000c184';

insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c183', 'Estudio 18');
insert into public.creative_posts (id, creative_id, title, category) values
  ('00000000-0000-0000-0000-0000000018b1', '00000000-0000-0000-0000-00000000c183', 'Render dudoso', 'render');
insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000018f1', '00000000-0000-0000-0000-00000000c182', 'published', 'Casa fraude', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

-- El cliente reporta la casa y la publicación
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c181", "role": "authenticated"}', true);
do $$ begin
  insert into public.reports (property_id, reason, details) values ('00000000-0000-0000-0000-0000000018f1', 'fraude', 'Pide anticipo por fuera');
  insert into public.reports (post_id, reason) values ('00000000-0000-0000-0000-0000000018b1', 'contenido_inapropiado');
  begin
    insert into public.reports (property_id, reason) values ('00000000-0000-0000-0000-0000000018f1', 'spam');
    raise exception 'FALLA: reportó dos veces lo mismo';
  exception when unique_violation then null;
  end;
  if (select count(*) from public.reports) <> 2 then raise exception 'FALLA: el cliente no ve sus reportes'; end if;
  begin
    perform public.resolve_report('propiedad', '00000000-0000-0000-0000-0000000018f1', 'ocultar');
    raise exception 'FALLA: un cliente ocultó una propiedad';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from public.admin_reports()) then raise exception 'FALLA: un cliente ve la bandeja del admin'; end if;
end $$;

-- Sin correo confirmado no puede reportar; el dueño no se reporta a sí mismo
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c185", "role": "authenticated"}', true);
do $$ begin
  insert into public.reports (property_id, reason) values ('00000000-0000-0000-0000-0000000018f1', 'spam');
  raise exception 'FALLA: reportó sin confirmar su correo';
exception when sqlstate 'P0001' then null;
end $$;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c182", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.reports) then raise exception 'FALLA: el vendedor ve quién lo reportó'; end if;
  insert into public.reports (property_id, reason) values ('00000000-0000-0000-0000-0000000018f1', 'spam');
  raise exception 'FALLA: se reportó a sí mismo';
exception when sqlstate 'P0001' then null;
end $$;

-- El admin ve la bandeja y oculta ambas
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c184", "role": "authenticated"}', true);
do $$ begin
  if (select count(*) from public.admin_reports()) <> 2 then raise exception 'FALLA: el admin no ve los 2 reportes'; end if;
  perform public.resolve_report('propiedad', '00000000-0000-0000-0000-0000000018f1', 'ocultar');
  perform public.resolve_report('publicacion', '00000000-0000-0000-0000-0000000018b1', 'ocultar');
  if exists (select 1 from public.admin_reports()) then raise exception 'FALLA: quedaron reportes abiertos'; end if;
end $$;

-- Ya no salen al público
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  if exists (select 1 from public.properties where id = '00000000-0000-0000-0000-0000000018f1') then raise exception 'FALLA: la casa oculta se ve'; end if;
  if exists (select 1 from public.creative_posts where id = '00000000-0000-0000-0000-0000000018b1') then raise exception 'FALLA: la publicación oculta se ve'; end if;
end $$;

-- El vendedor no la puede volver a publicar; el creativo sí ve la suya pero no la des-oculta
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c182", "role": "authenticated"}', true);
do $$ begin
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-0000000018f1';
  raise exception 'FALLA: el vendedor republicó una casa ocultada por reporte';
exception when sqlstate 'ZA005' then null;
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c183", "role": "authenticated"}', true);
do $$ begin
  update public.creative_posts set hidden = false, title = 'Render corregido' where id = '00000000-0000-0000-0000-0000000018b1';
  if not (select hidden from public.creative_posts where id = '00000000-0000-0000-0000-0000000018b1') then
    raise exception 'FALLA: el creativo des-ocultó su publicación';
  end if;
end $$;

reset role;
select 'REPORTES OK' as resultado;
rollback;

-- 0019_prueba_leads_vistos.sql
-- Prueba de "visto" en los leads (ZAI-35). Resultado: LEADS VISTOS OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d191', 'cliente.19@zaisanfy.test',  now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d192', 'vendedor.19@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000d193', 'otro.19@zaisanfy.test',     now(), '{"role": "vendedor"}');
insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000019f1', '00000000-0000-0000-0000-00000000d192', 'published', 'Casa 19', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d191", "role": "authenticated"}', true);
insert into public.contact_requests (id, property_id) values ('00000000-0000-0000-0000-0000000019c1', '00000000-0000-0000-0000-0000000019f1');

-- Otro vendedor no lo puede marcar
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d193", "role": "authenticated"}', true);
do $$ begin
  if public.mark_inbox_seen(array['00000000-0000-0000-0000-0000000019c1'::uuid]) <> 0 then raise exception 'FALLA: otro vendedor marcó el lead'; end if;
end $$;

-- El dueño lo ve como nuevo, lo abre y queda visto (una sola vez)
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d192", "role": "authenticated"}', true);
do $$ begin
  if (select seen_at from public.my_inbox()) is not null then raise exception 'FALLA: el lead nuevo ya sale visto'; end if;
  if public.mark_inbox_seen(array['00000000-0000-0000-0000-0000000019c1'::uuid]) <> 1 then raise exception 'FALLA: no se marcó'; end if;
  if public.mark_inbox_seen(array['00000000-0000-0000-0000-0000000019c1'::uuid]) <> 0 then raise exception 'FALLA: se marcó dos veces'; end if;
  if (select seen_at from public.my_inbox()) is null then raise exception 'FALLA: no sale como visto'; end if;
  begin
    update public.contact_requests set seen_at = null where id = '00000000-0000-0000-0000-0000000019c1';
    raise exception 'FALLA: se cambió seen_at a mano';
  exception when insufficient_privilege then null;
  end;
end $$;

-- El cliente sabe que ya lo vieron
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d191", "role": "authenticated"}', true);
do $$ begin
  if (select seen_at from public.contact_requests where id = '00000000-0000-0000-0000-0000000019c1') is null then
    raise exception 'FALLA: el cliente no ve que ya lo vieron';
  end if;
end $$;

reset role;
select 'LEADS VISTOS OK' as resultado;
rollback;

-- 0020_prueba_mejoras_negocio.sql
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

-- 0021_prueba_super_admin.sql
-- Prueba del panel del Super Admin (RF-ADM-01 a 03). Resultado: SUPER ADMIN OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d211', 'admin.21@zaisanfy.test',    now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d212', 'vendedor.21@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000d213', 'creativo.21@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000d214', 'cliente.21@zaisanfy.test',  now(), '{"role": "visitante"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000d211';

insert into public.properties (id, seller_id, status, title, description, operation, property_type, price, state, city, lat, lng, area_m2, neighborhood) values
  ('00000000-0000-0000-0000-0000000021f1', '00000000-0000-0000-0000-00000000d212', 'published', 'Casa completa con jardín en Zapopan centro',
   repeat('Descripción larga. ', 20), 'venta', 'casa', 100, 'Jalisco', 'Zapopan', 20.7, -103.4, 120, 'Centro'),
  ('00000000-0000-0000-0000-0000000021f2', '00000000-0000-0000-0000-00000000d212', 'published', 'Casa', null, 'venta', 'casa', 100, 'Jalisco', 'Zapopan', null, null, null, null);
insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000d213', 'Estudio 21');
insert into public.creative_posts (id, creative_id, title, category) values
  ('00000000-0000-0000-0000-0000000021b1', '00000000-0000-0000-0000-00000000d213', 'Render 21', 'render');

-- Métricas antes de los pagos de prueba: en producción ya hay suscripciones reales,
-- así que se compara la diferencia y no el total.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d211", "role": "authenticated"}', true);
select set_config('prueba.mrr_antes', mrr::text, true), set_config('prueba.churn_antes', churned::text, true)
from public.admin_metrics(3) limit 1;
reset role;

-- Pagos para las métricas: una Pro viva y un cambio de plan (no es churn)
insert into public.subscriptions (user_id, plan_id, status, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000d212', 'pro', 'activa', now() - interval '40 days', now()),
  ('00000000-0000-0000-0000-00000000d213', 'pro', 'cancelada', now() - interval '40 days', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-00000000d213', 'enterprise', 'activa', now() - interval '1 hour', now());

-- Un cliente no ve nada del admin
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d214", "role": "authenticated"}', true);
do $$ begin
  begin perform public.admin_users(); raise exception 'FALLA: un cliente ve los usuarios';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_set_suspended('00000000-0000-0000-0000-00000000d212', true); raise exception 'FALLA: un cliente suspendió';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_metrics(); raise exception 'FALLA: un cliente ve las métricas';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_seo_scores(); raise exception 'FALLA: un cliente ve el SEO Score';
  exception when insufficient_privilege then null; end;
  if exists (select 1 from public.suspensions) then raise exception 'FALLA: un cliente ve las suspensiones'; end if;
end $$;

-- El admin: usuarios, detalle, SEO, métricas y suspensión
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d211", "role": "authenticated"}', true);
do $$
declare
  d jsonb;
  m record;
begin
  if (select count(*) from public.admin_users('21@zaisanfy')) <> 4 then raise exception 'FALLA: el admin no ve los usuarios'; end if;
  if (select plan from public.admin_users('vendedor.21')) <> 'pro' then raise exception 'FALLA: no sale el plan del usuario'; end if;

  d := public.admin_user_detail('00000000-0000-0000-0000-00000000d212');
  if jsonb_array_length(d->'properties') <> 2 then raise exception 'FALLA: ver como no muestra sus propiedades'; end if;

  if (select score from public.admin_seo_scores() where id = '00000000-0000-0000-0000-0000000021f1') < 50
     or (select score from public.admin_seo_scores() where id = '00000000-0000-0000-0000-0000000021f2') > 30 then
    raise exception 'FALLA: el SEO Score no distingue la propiedad completa de la vacía';
  end if;
  if not exists (select 1 from public.admin_seo_scores() where id = '00000000-0000-0000-0000-0000000021f2' and 'Ubicación en el mapa (GEO)' = any (tips)) then
    raise exception 'FALLA: el SEO Score no sugiere la ubicación';
  end if;

  select * into m from public.admin_metrics(3) limit 1;
  if m.mrr - current_setting('prueba.mrr_antes')::numeric < 499 + 1499 then raise exception 'FALLA: el MRR no suma las suscripciones vivas (%)', m.mrr; end if;
  if m.churned <> current_setting('prueba.churn_antes')::bigint then raise exception 'FALLA: un cambio de plan contó como churn'; end if;

  begin perform public.admin_set_suspended('00000000-0000-0000-0000-00000000d211', true); raise exception 'FALLA: el admin se suspendió solo';
  exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;

  perform public.admin_set_suspended('00000000-0000-0000-0000-00000000d212', true, 'Fraude');
  perform public.admin_set_role('00000000-0000-0000-0000-00000000d214', 'creativo');
  if (select role from public.profiles where id = '00000000-0000-0000-0000-00000000d214') <> 'creativo' then raise exception 'FALLA: no cambió el rol'; end if;
  if not exists (select 1 from public.properties where seller_id = '00000000-0000-0000-0000-00000000d212') then
    raise exception 'FALLA: el admin dejó de ver lo del suspendido';
  end if;
end $$;

-- El público ya no ve lo del suspendido
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  if exists (select 1 from public.properties where seller_id = '00000000-0000-0000-0000-00000000d212') then
    raise exception 'FALLA: se siguen viendo las propiedades del suspendido';
  end if;
end $$;

-- El suspendido no puede escribir nada
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d212", "role": "authenticated"}', true);
do $$ begin
  if not public.am_suspended() then raise exception 'FALLA: el suspendido no sabe que lo está'; end if;
  begin
    update public.properties set title = 'Me desuspendo' where id = '00000000-0000-0000-0000-0000000021f1';
    if found then raise exception 'FALLA: el suspendido editó su propiedad'; end if;
  exception when sqlstate 'ZA007' then null;
  end;
  begin
    insert into public.bookmarks (property_id) values ('00000000-0000-0000-0000-0000000021f1');
    raise exception 'FALLA: el suspendido guardó en Mi Lista';
  exception when sqlstate 'ZA007' then null;
  end;
end $$;

-- Reactivar
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d211", "role": "authenticated"}', true);
select public.admin_set_suspended('00000000-0000-0000-0000-00000000d212', false);
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  if (select count(*) from public.properties where seller_id = '00000000-0000-0000-0000-00000000d212') <> 2 then
    raise exception 'FALLA: al reactivar no regresaron sus propiedades';
  end if;
end $$;

reset role;
rollback;

select 'SUPER ADMIN OK' as resultado;

-- 0022_prueba_impersonate.sql
-- Prueba del "impersonate" del admin (RF-ADM-01). Resultado: IMPERSONATE OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000e221', 'admin.22@zaisanfy.test',    now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000e222', 'vendedor.22@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000e223', 'admin2.22@zaisanfy.test',   now(), '{"role": "visitante"}');
update public.profiles set role = 'admin' where id in ('00000000-0000-0000-0000-00000000e221', '00000000-0000-0000-0000-00000000e223');

set local role authenticated;

-- Un no-admin no puede, ni ve la bitácora, ni escribe en ella
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e222", "role": "authenticated"}', true);
do $$ begin
  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-00000000e223'); raise exception 'FALLA: un vendedor entró como otro';
  exception when insufficient_privilege then null; end;
  begin insert into public.impersonations (admin_id, target_id) values (auth.uid(), auth.uid()); raise exception 'FALLA: se escribió la bitácora directo';
  exception when insufficient_privilege then null; end;
end $$;

-- El admin
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e221", "role": "authenticated"}', true);
do $$
declare r record;
begin
  select * into r from public.admin_start_impersonation('00000000-0000-0000-0000-00000000e222', 'Soporte');
  if r.email <> 'vendedor.22@zaisanfy.test' or r.role <> 'vendedor' then raise exception 'FALLA: no regresó el correo y rol correctos'; end if;
  if (select count(*) from public.impersonations where target_id = '00000000-0000-0000-0000-00000000e222' and reason = 'Soporte') <> 1 then
    raise exception 'FALLA: no quedó en la bitácora';
  end if;

  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-00000000e221'); raise exception 'FALLA: entró como sí mismo';
  exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-00000000e223'); raise exception 'FALLA: entró como otro admin';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-0000000fffff'); raise exception 'FALLA: usuario inexistente';
  exception when no_data_found then null; end;
end $$;

reset role;
rollback;

select 'IMPERSONATE OK' as resultado;

select 'TODAS LAS PRUEBAS OK' as resultado;
