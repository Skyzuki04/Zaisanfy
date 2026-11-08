-- ZAI-38 · GEO-01: búsqueda por isocronas (propiedades a X minutos de un punto)
-- Usa la 0012 porque la 0011 la tiene apartada Minette.

-- PostGIS: geografía en Postgres. En Supabase va en el esquema extensions, no en public.
create extension if not exists postgis with schema extensions;

-- Punto de cada propiedad, calculado solo a partir de lat y lng (no se escribe a mano).
-- SRID 4326 = coordenadas GPS normales (las mismas que usan Mapbox, Google y Leaflet).
alter table public.properties
  add column geom extensions.geometry(Point, 4326)
  generated always as (
    case when lat is not null and lng is not null
         then extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)
    end
  ) stored;

comment on column public.properties.geom is 'Punto (lng, lat) para búsquedas geográficas. Se calcula solo; no se edita.';

-- Índice espacial: sin él, Postgres revisaría propiedad por propiedad
create index if not exists properties_geom_idx on public.properties using gist (geom);

-- Propiedades dentro de una zona (la isocrona que regresa Mapbox, en GeoJSON).
-- security invoker: respeta RLS, así que un visitante solo recibe propiedades publicadas.
-- Devuelve filas de properties para que el Escaparate pueda seguir filtrando y pidiendo las fotos.
create or replace function public.properties_in_zone(zone jsonb)
returns setof public.properties
language sql
stable
security invoker
set search_path = ''
as $$
  with z as (
    select extensions.st_setsrid(extensions.st_geomfromgeojson(zone::text), 4326) as g
    where jsonb_typeof(zone) = 'object'
      and zone->>'type' in ('Polygon', 'MultiPolygon')
      and octet_length(zone::text) <= 500000   -- una isocrona normal pesa unos pocos KB
  )
  select p.*
  from public.properties p, z
  where p.geom is not null
    and extensions.st_intersects(p.geom, z.g);
$$;

comment on function public.properties_in_zone(jsonb) is 'ZAI-38: propiedades cuyo punto cae dentro del polígono GeoJSON (Polygon o MultiPolygon).';

revoke execute on function public.properties_in_zone(jsonb) from public;
grant execute on function public.properties_in_zone(jsonb) to anon, authenticated;
