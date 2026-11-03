-- =====================================================================
-- TODAS LAS PRUEBAS JUNTAS (0002 a 0007)
-- Corre una tras otra las pruebas de permisos, perfiles, portafolio, Mi Lista,
-- solicitudes y mejora de cuenta. Cada una hace ROLLBACK: NO deja datos.
--
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
--   - Si todo está bien, el resultado final dice "TODAS LAS PRUEBAS OK".
--   - Si algo falla, se detiene y sale un error que empieza con "FALLA:"
--     (dice qué regla no se cumplió).
-- Las MIGRACIONES no van aquí: esas se corren una sola vez.
-- Este archivo se arma juntando los de esta carpeta; si cambias una prueba, actualízalo también.
-- =====================================================================

-- ##################### 0002_prueba_permisos.sql #####################
-- =====================================================================
-- ZAI-20 · Prueba de permisos con 2 vendedores y 1 visitante
-- Crea usuarios de prueba, se hace pasar por cada uno y revisa qué puede
-- ver y editar. Al final hace ROLLBACK: no deja nada guardado.
-- Si todo sale bien, el último resultado dice "ZAI-20 OK".
-- Si algo falla, sale un error que empieza con "FALLA:".
--
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
-- =====================================================================
begin;

-- Usuarios de prueba (el trigger les crea el perfil con su rol)
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'vendedora.a@zaisanfy.test', '{"role": "vendedor", "full_name": "Vendedora A"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'vendedor.b@zaisanfy.test',  '{"role": "vendedor", "full_name": "Vendedor B"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'visitante@zaisanfy.test',   '{"role": "admin"}');  -- pide admin a propósito

-- Una propiedad publicada y una en borrador de cada vendedor
insert into public.properties (seller_id, status, data)
select s.id, st.status::public.property_status,
       jsonb_build_object('title', 'Prueba ' || st.status || ' ' || s.tag, 'propertyType', 'casa',
                          'price', 1000000, 'location', jsonb_build_object('state', 'Jalisco', 'city', 'Zapopan'))
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

-- ---------- Visitante sin sesión (anon) ----------
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  if exists (select 1 from public.properties where status <> 'published') then
    raise exception 'FALLA: sin sesión se ven propiedades no publicadas';
  end if;
  if not exists (select 1 from public.properties where data->>'title' = 'Prueba published A') then
    raise exception 'FALLA: sin sesión no se ven las publicadas';
  end if;
  begin
    insert into public.properties (seller_id, data)
    values ('00000000-0000-0000-0000-0000000000a1', '{"title": "Intruso", "propertyType": "casa", "price": 1, "location": {"city": "Puebla"}}');
    raise exception 'FALLA: sin sesión se pudo crear una propiedad';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------- Vendedora A ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);

do $$
declare n int;
begin
  if not exists (select 1 from public.properties where data->>'title' = 'Prueba draft A') then
    raise exception 'FALLA: A no ve su propio borrador';
  end if;
  if exists (select 1 from public.properties where data->>'title' = 'Prueba draft B') then
    raise exception 'FALLA: A ve el borrador de B';
  end if;

  update public.properties set status = 'hidden' where data->>'title' = 'Prueba published B';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: A pudo editar una propiedad de B'; end if;

  delete from public.properties where data->>'title' = 'Prueba published B';
  get diagnostics n = row_count;
  if n > 0 then raise exception 'FALLA: A pudo borrar una propiedad de B'; end if;

  update public.properties set status = 'published' where data->>'title' = 'Prueba draft A';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: A no pudo publicar su propia propiedad'; end if;

  begin
    update public.properties set seller_id = '00000000-0000-0000-0000-0000000000b2' where data->>'title' = 'Prueba published A';
    raise exception 'FALLA: A pudo pasarle su propiedad a B';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.properties (seller_id, data)
    values ('00000000-0000-0000-0000-0000000000b2', '{"title": "A nombre de B", "propertyType": "casa", "price": 1, "location": {"city": "Puebla"}}');
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

-- ---------- Visitante con sesión ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000c3", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.properties (seller_id, data)
    values ('00000000-0000-0000-0000-0000000000c3', '{"title": "No soy vendedor", "propertyType": "casa", "price": 1, "location": {"city": "Puebla"}}');
    raise exception 'FALLA: un visitante pudo crear una propiedad';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from public.properties where status <> 'published') then
    raise exception 'FALLA: un visitante ve propiedades no publicadas';
  end if;
end $$;

-- ---------- Admin (solo se asigna desde el SQL Editor) ----------
reset role;
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000c3';
set local role authenticated;

do $$ begin
  if not exists (select 1 from public.properties where data->>'title' = 'Prueba draft B') then
    raise exception 'FALLA: el admin no ve los borradores';
  end if;
  if (select count(*) from public.profiles) < 3 then
    raise exception 'FALLA: el admin no ve todos los perfiles';
  end if;
end $$;

reset role;
rollback;

-- Si llegó hasta aquí, todas las revisiones pasaron
select 'ZAI-20 OK' as resultado;

-- ##################### 0003_prueba_perfiles.sql #####################
-- =====================================================================
-- ZAI-27 · Prueba de permisos del perfil de creativo
-- Crea 2 creativos y 1 vendedor, se hace pasar por cada uno (y por un
-- visitante sin sesión) y revisa qué puede ver y editar.
-- Al final hace ROLLBACK: no deja datos.
-- Si todo sale bien, el resultado dice "ZAI-27 OK".
-- Si algo falla, sale un error que empieza con "FALLA:".
-- Requiere 0003_creative_profiles.sql.
-- =====================================================================
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000c001', 'creativa.a@zaisanfy.test', '{"role": "creativo", "full_name": "Creativa A"}'),
  ('00000000-0000-0000-0000-00000000c002', 'creativo.b@zaisanfy.test', '{"role": "creativo", "full_name": "Creativo B"}'),
  ('00000000-0000-0000-0000-00000000c003', 'vendedor.c@zaisanfy.test', '{"role": "vendedor", "full_name": "Vendedor C"}');

-- ---------- Creativa A ----------
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

-- ---------- Creativo B ----------
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

-- ---------- Vendedor C: no puede tener perfil de creativo ----------
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

-- ---------- Visitante sin sesión: ve los perfiles, no edita ----------
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

-- Si llegó hasta aquí, todas las revisiones pasaron
select 'ZAI-27 OK' as resultado;

-- ##################### 0004_prueba_portafolio.sql #####################
-- =====================================================================
-- ZAI-28 · Prueba de permisos del portafolio (y repaso de perfiles)
-- Crea 2 creativos, 1 vendedor y 1 visitante, se hace pasar por cada uno
-- y revisa qué puede ver y editar. Al final hace ROLLBACK: no deja datos.
-- Si todo sale bien, el resultado dice "ZAI-28 OK".
-- Si algo falla, sale un error que empieza con "FALLA:".
-- Requiere 0003_creative_profiles.sql y 0004_creative_posts.sql.
-- =====================================================================
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000c001', 'creativa.a@zaisanfy.test', '{"role": "creativo", "full_name": "Creativa A"}'),
  ('00000000-0000-0000-0000-00000000c002', 'creativo.b@zaisanfy.test', '{"role": "creativo", "full_name": "Creativo B"}'),
  ('00000000-0000-0000-0000-00000000c003', 'vendedor.c@zaisanfy.test', '{"role": "vendedor", "full_name": "Vendedor C"}');

-- ---------- Creativa A ----------
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

  insert into public.creative_posts (creative_id, title, category, images, property_type, city)
  values ('00000000-0000-0000-0000-00000000c001', 'Render de sala', 'render', array['https://res.cloudinary.com/x/image/upload/a.jpg'], 'casa', 'Zapopan');

  begin
    insert into public.creative_posts (creative_id, title, category, images)
    values ('00000000-0000-0000-0000-00000000c001', 'Sin imágenes', 'idea', array[]::text[]);
    raise exception 'FALLA: se guardó una publicación sin imágenes';
  exception when check_violation then null;
  end;
end $$;

-- ---------- Creativo B ----------
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
    insert into public.creative_posts (creative_id, title, category, images)
    values ('00000000-0000-0000-0000-00000000c001', 'A nombre de A', 'idea', array['https://res.cloudinary.com/x/image/upload/b.jpg']);
    raise exception 'FALLA: B publicó en el portafolio de A';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------- Vendedor C: no puede tener perfil de creativo ----------
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

-- ---------- Visitante sin sesión: ve perfiles y portafolios, no edita ----------
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

-- Si llegó hasta aquí, todas las revisiones pasaron
select 'ZAI-28 OK' as resultado;

-- ##################### 0005_prueba_mi_lista.sql #####################
-- =====================================================================
-- ZAI-31 · Prueba de "Mi Lista" con 2 visitantes
-- Al final hace ROLLBACK: no deja datos.
-- Si todo sale bien, el resultado dice "ZAI-31 OK".
-- Requiere 0005_bookmarks.sql.
-- =====================================================================
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d001', 'visitante.a@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d002', 'visitante.b@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d003', 'vendedor.d@zaisanfy.test', '{"role": "vendedor"}');

insert into public.properties (id, seller_id, status, data) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000d003', 'published',
   '{"title": "Publicada de prueba", "propertyType": "casa", "price": 100, "location": {"state": "Jalisco", "city": "Zapopan"}}'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-00000000d003', 'draft',
   '{"title": "Borrador de prueba", "propertyType": "casa", "price": 100, "location": {"state": "Jalisco", "city": "Zapopan"}}');

-- ---------- Visitante A ----------
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

-- ---------- Visitante B ----------
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

-- ---------- A quita de su lista ----------
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

-- ---------- Sin sesión no hay lista ----------
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

-- ##################### 0006_prueba_solicitudes.sql #####################
-- =====================================================================
-- ZAI-33 · Prueba de solicitudes de contacto (visita y cotización)
-- Al final hace ROLLBACK: no deja datos.
-- Si todo sale bien, el resultado dice "ZAI-33 OK".
-- Requiere 0006_contact_requests.sql.
-- =====================================================================
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000e001', 'cliente.a@zaisanfy.test', now(), '{"role": "visitante", "full_name": "Cliente A"}'),
  ('00000000-0000-0000-0000-00000000e002', 'cliente.b@zaisanfy.test', now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000e003', 'vendedor.e@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000e004', 'creativo.e@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000e005', 'sin.confirmar@zaisanfy.test', null, '{"role": "visitante"}');

insert into public.properties (id, seller_id, status, data) values
  ('00000000-0000-0000-0000-0000000001f1', '00000000-0000-0000-0000-00000000e003', 'published',
   '{"title": "Publicada de prueba", "propertyType": "casa", "price": 100, "location": {"state": "Jalisco", "city": "Zapopan"}}'),
  ('00000000-0000-0000-0000-0000000001f2', '00000000-0000-0000-0000-00000000e003', 'draft',
   '{"title": "Borrador de prueba", "propertyType": "casa", "price": 100, "location": {"state": "Jalisco", "city": "Zapopan"}}');

insert into public.creative_profiles (id, display_name, specialty) values
  ('00000000-0000-0000-0000-00000000e004', 'Estudio de prueba', 'interiorismo');

-- ---------- Cliente A ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e001", "role": "authenticated"}', true);

do $$
declare r public.contact_requests;
begin
  -- intenta mandarla "a nombre de otro" y a otro destinatario: la base de datos lo corrige
  insert into public.contact_requests (kind, property_id, recipient_id, requester_id, requester_name, message)
  values ('visita', '00000000-0000-0000-0000-0000000001f1', '00000000-0000-0000-0000-00000000e002',
          '00000000-0000-0000-0000-00000000e002', 'Nombre falso', 'Me interesa')
  returning * into r;
  if r.recipient_id <> '00000000-0000-0000-0000-00000000e003' then raise exception 'FALLA: el destinatario no es el vendedor'; end if;
  if r.requester_id <> '00000000-0000-0000-0000-00000000e001' then raise exception 'FALLA: se mandó a nombre de otro'; end if;
  if r.requester_name <> 'Cliente A' or r.requester_email <> 'cliente.a@zaisanfy.test' then raise exception 'FALLA: no se copiaron los datos del cliente'; end if;

  begin
    insert into public.contact_requests (kind, property_id) values ('visita', '00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: dos solicitudes abiertas para la misma propiedad';
  exception when raise_exception then
    if sqlerrm not like '%abierta%' then raise exception 'FALLA: una abierta por propiedad (%)', sqlerrm; end if;
  end;

  begin
    insert into public.contact_requests (kind, property_id) values ('visita', '00000000-0000-0000-0000-0000000001f2');
    raise exception 'FALLA: se pidió visita a una propiedad no publicada';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;

  insert into public.contact_requests (kind, creative_id, message) values ('cotizacion', '00000000-0000-0000-0000-00000000e004', 'Cotización');
  if (select count(*) from public.contact_requests) <> 2 then raise exception 'FALLA: A no ve sus solicitudes'; end if;

  -- el cliente no puede cambiar el estado
  update public.contact_requests set status = 'cerrada';
  if exists (select 1 from public.contact_requests where status <> 'nueva') then raise exception 'FALLA: el cliente cambió el estado'; end if;
end $$;

-- ---------- Cliente B no ve lo de A; límite de 5 por día ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);

do $$
declare i int;
begin
  if exists (select 1 from public.contact_requests) then raise exception 'FALLA: B ve solicitudes de A'; end if;
end $$;

-- B manda 5 solicitudes y el vendedor cierra cada una, para no chocar con la regla de "una abierta"
do $$ begin
  for i in 1..5 loop
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);
    insert into public.contact_requests (kind, property_id) values ('visita', '00000000-0000-0000-0000-0000000001f1');
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e003", "role": "authenticated"}', true);
    update public.contact_requests set status = 'cerrada' where requester_id = '00000000-0000-0000-0000-00000000e002';
  end loop;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);
end $$;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.contact_requests (kind, creative_id) values ('cotizacion', '00000000-0000-0000-0000-00000000e004');
    raise exception 'FALLA: no se aplicó el límite de 5 por día';
  exception when raise_exception then
    if sqlerrm not like '%límite%' then raise exception 'FALLA: límite de 5 por día (%)', sqlerrm; end if;
  end;
end $$;

-- ---------- El vendedor ve y atiende solo lo suyo ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e003", "role": "authenticated"}', true);

do $$
declare n int;
begin
  if exists (select 1 from public.contact_requests where kind = 'cotizacion') then raise exception 'FALLA: el vendedor ve cotizaciones del creativo'; end if;
  update public.contact_requests set status = 'contactado' where requester_id = '00000000-0000-0000-0000-00000000e001';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: el vendedor no pudo cambiar el estado'; end if;

  begin
    update public.contact_requests set message = 'cambiado' where requester_id = '00000000-0000-0000-0000-00000000e001';
    raise exception 'FALLA: el vendedor cambió el mensaje del cliente';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.contact_requests (kind, property_id) values ('visita', '00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: el vendedor se contactó a sí mismo';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
end $$;

-- ---------- El creativo ve su cotización ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e004", "role": "authenticated"}', true);

do $$ begin
  if (select count(*) from public.contact_requests) <> 1 then raise exception 'FALLA: el creativo no ve solo su cotización'; end if;
end $$;

-- ---------- Correo sin confirmar ----------
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e005", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.contact_requests (kind, property_id) values ('visita', '00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: se aceptó una solicitud con el correo sin confirmar';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
end $$;

-- ---------- Sin sesión no hay nada ----------
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  begin
    if exists (select 1 from public.contact_requests) then raise exception 'FALLA: sin sesión se ven solicitudes'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.contact_requests (kind, property_id) values ('visita', '00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: sin sesión se pudo enviar una solicitud';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;

select 'ZAI-33 OK' as resultado;

-- ##################### 0007_prueba_mejora_de_cuenta.sql #####################
-- =====================================================================
-- Prueba de la mejora de cuenta (upgrade_role)
-- Al final hace ROLLBACK: no deja datos.
-- Si todo sale bien, el resultado dice "MEJORA DE CUENTA OK".
-- Requiere 0007_upgrade_role.sql.
-- =====================================================================
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000f001', 'cliente.f@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000f002', 'cliente.g@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000f003', 'vendedor.f@zaisanfy.test', '{"role": "vendedor"}');

-- ---------- Cliente F se vuelve vendedor ----------
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

  -- ya es vendedor: no puede cambiar a creativo ni regresar a visitante
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

  -- sigue sin poder editar el rol directamente
  begin
    update public.profiles set role = 'admin' where id = auth.uid();
    raise exception 'FALLA: se editó el rol sin el RPC';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ---------- Cliente G se vuelve creativo; no toca a nadie más ----------
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

-- ---------- Sin sesión no se puede ----------
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

select 'TODAS LAS PRUEBAS OK' as resultado;
