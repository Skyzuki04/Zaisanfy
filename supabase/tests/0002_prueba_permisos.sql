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
