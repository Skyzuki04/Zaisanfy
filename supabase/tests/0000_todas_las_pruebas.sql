-- Todas las pruebas (0002 a 0009). Cada una hace ROLLBACK y no deja datos.
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
  returning * into r;
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
  if exists (select 1 from public.property_photos where url like 'https://x.test/%') then raise exception 'FALLA: sin sesión se ven fotos de un borrador'; end if;
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

-- 0009_prueba_pagos.sql
-- Prueba de pagos
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000a901', 'vendedor.a9@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000a902', 'vendedor.b9@zaisanfy.test', now(), '{"role": "vendedor"}');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000009f1', '00000000-0000-0000-0000-00000000a901', 'published', 'Anunciada', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

-- Lo que haría el webhook de Stripe (como servidor)
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

-- Vendedor B no ve nada de A y su plan es Freemium
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a902", "role": "authenticated"}', true);

do $$ begin
  if public.my_plan() <> 'freemium' then raise exception 'FALLA: B no quedó en Freemium'; end if;
  if exists (select 1 from public.payments) or exists (select 1 from public.subscriptions) then raise exception 'FALLA: B ve pagos de A'; end if;
  if (select count(*) from public.plans) <> 3 then raise exception 'FALLA: no se ven los 3 planes'; end if;
end $$;

-- Sin sesión: se ve el anuncio vigente y se cuenta la vista
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

select 'TODAS LAS PRUEBAS OK' as resultado;
