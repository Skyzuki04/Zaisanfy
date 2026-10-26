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
