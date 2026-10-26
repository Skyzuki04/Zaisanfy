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
