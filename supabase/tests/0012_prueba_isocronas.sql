-- Prueba de búsqueda por isocronas (ZAI-38 · GEO-01). Resultado: ISOCRONAS OK
-- 3 puntos en ciudades distintas (CDMX, Guadalajara, Monterrey). En cada una hay una casa dentro
-- de la zona y otra fuera. La zona es un polígono como el que regresa Mapbox.
-- Solo se cuentan las propiedades de esta prueba, para que no estorben las que ya hay en la base.
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000ab01', 'vendedor.a12@zaisanfy.test', '{"role": "vendedor"}');

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
