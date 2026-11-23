-- ZAI-39 · SRV-01: fotógrafos 360 bajo demanda ("uberización").
-- El vendedor pide un fotógrafo para una propiedad con fecha. Los creativos con especialidad
-- "fotografia" que estén cerca (dentro de su radio de trabajo) ven la solicitud y uno la acepta.
-- Estados: pedido → aceptado → en_camino → terminado (o cancelado). Avisos en vivo con Supabase Realtime.
-- Necesita PostGIS (migración 0012).

create type public.service_status as enum ('pedido', 'aceptado', 'en_camino', 'terminado', 'cancelado');

-- Zona de trabajo del fotógrafo
alter table public.creative_profiles
  add column base_lat double precision check (base_lat is null or base_lat between -90 and 90),
  add column base_lng double precision check (base_lng is null or base_lng between -180 and 180),
  add column service_radius_km integer not null default 25 check (service_radius_km between 1 and 200);

comment on column public.creative_profiles.service_radius_km is 'ZAI-39: hasta cuántos km acepta trabajos de fotografía 360.';

create table public.service_requests (
  id              uuid primary key default gen_random_uuid(),
  seller_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  property_id     uuid not null references public.properties (id) on delete cascade,
  photographer_id uuid references public.creative_profiles (id) on delete set null,
  scheduled_at    timestamptz not null,
  address         text not null check (length(trim(address)) between 5 and 300),
  lat             double precision not null check (lat between -90 and 90),
  lng             double precision not null check (lng between -180 and 180),
  notes           text check (notes is null or length(notes) <= 500),
  status          public.service_status not null default 'pedido',
  accepted_at     timestamptz,
  finished_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check ((status = 'pedido') = (photographer_id is null) or status = 'cancelado')
);

comment on table public.service_requests is 'ZAI-39: pedidos de fotógrafo 360 a domicilio.';

create index service_requests_seller_idx on public.service_requests (seller_id, created_at desc);
create index service_requests_photographer_idx on public.service_requests (photographer_id, scheduled_at);
create index service_requests_open_idx on public.service_requests (status, scheduled_at) where status = 'pedido';
create unique index service_requests_one_open on public.service_requests (property_id)
  where status in ('pedido', 'aceptado', 'en_camino');

create trigger service_requests_set_updated_at
before update on public.service_requests
for each row execute function public.set_updated_at();

-- Distancia en km entre dos puntos GPS
create or replace function public.km_between(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select extensions.st_distance(
    extensions.st_setsrid(extensions.st_makepoint(lng1, lat1), 4326)::extensions.geography,
    extensions.st_setsrid(extensions.st_makepoint(lng2, lat2), 4326)::extensions.geography
  ) / 1000.0;
$$;

-- ¿Soy fotógrafo y esta solicitud está dentro de mi radio?
create or replace function public.service_is_near_me(p_lat double precision, p_lng double precision)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.creative_profiles c
    where c.id = auth.uid() and c.specialty = 'fotografia' and c.base_lat is not null and c.base_lng is not null
      and public.km_between(c.base_lat, c.base_lng, p_lat, p_lng) <= c.service_radius_km
  );
$$;

-- Alta: siempre a nombre del vendedor dueño de la propiedad, con fecha futura y en estado "pedido"
create or replace function public.service_requests_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.properties;
begin
  new.seller_id := auth.uid();
  select * into p from public.properties where id = new.property_id;
  if p.id is null or p.seller_id is distinct from new.seller_id then
    raise exception 'Solo puedes pedir fotógrafo para tus propiedades' using errcode = '42501';
  end if;
  if new.scheduled_at < now() + interval '2 hours' then
    raise exception 'Pide el fotógrafo con al menos 2 horas de anticipación' using errcode = 'P0001';
  end if;
  if new.scheduled_at > now() + interval '60 days' then
    raise exception 'Solo se puede agendar hasta 60 días adelante' using errcode = 'P0001';
  end if;
  new.lat := coalesce(new.lat, p.lat);
  new.lng := coalesce(new.lng, p.lng);
  if new.lat is null or new.lng is null then
    raise exception 'La propiedad no tiene ubicación en el mapa. Agrégale latitud y longitud.' using errcode = 'P0001';
  end if;
  new.address := coalesce(nullif(trim(new.address), ''),
                          concat_ws(', ', p.address, p.neighborhood, p.city, p.state));
  new.status := 'pedido';
  new.photographer_id := null;
  new.accepted_at := null;
  new.finished_at := null;
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

create trigger service_requests_before_insert
before insert on public.service_requests
for each row execute function public.service_requests_before_insert();

-- Permisos: insertar y leer por RLS; los cambios de estado solo por las funciones de abajo
revoke all on public.service_requests from anon;
revoke update, delete on public.service_requests from authenticated;
alter table public.service_requests enable row level security;

create policy "El vendedor pide fotógrafo"
on public.service_requests for insert to authenticated
with check (seller_id = (select auth.uid()));

create policy "El vendedor ve sus pedidos"
on public.service_requests for select to authenticated
using (seller_id = (select auth.uid()));

create policy "El fotógrafo ve sus trabajos"
on public.service_requests for select to authenticated
using (photographer_id = (select auth.uid()));

create policy "Los fotógrafos cercanos ven los pedidos libres"
on public.service_requests for select to authenticated
using (status = 'pedido' and scheduled_at > now() and public.service_is_near_me(lat, lng));

create policy "Admin ve todos los pedidos de fotógrafo"
on public.service_requests for select to authenticated
using ((select public.my_role()) = 'admin');

-- El fotógrafo toma un pedido. Si dos lo aceptan al mismo tiempo, solo gana uno.
create or replace function public.accept_service(p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.service_requests;
begin
  select * into r from public.service_requests where id = p_request for update;
  if r.id is null then
    raise exception 'Este pedido ya no existe' using errcode = 'P0001';
  end if;
  if r.status <> 'pedido' then
    raise exception 'Otro fotógrafo ya tomó este pedido' using errcode = 'ZA004';
  end if;
  if not public.service_is_near_me(r.lat, r.lng) then
    raise exception 'Este pedido está fuera de tu zona de trabajo' using errcode = '42501';
  end if;
  update public.service_requests
     set photographer_id = auth.uid(), status = 'aceptado', accepted_at = now()
   where id = p_request;
end;
$$;

-- El fotógrafo avanza: aceptado → en_camino → terminado
create or replace function public.advance_service(p_request uuid)
returns public.service_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_next public.service_status;
begin
  update public.service_requests
     set status = case status when 'aceptado' then 'en_camino'::public.service_status else 'terminado'::public.service_status end,
         finished_at = case when status = 'en_camino' then now() else finished_at end
   where id = p_request and photographer_id = auth.uid() and status in ('aceptado', 'en_camino')
  returning status into v_next;
  if v_next is null then
    raise exception 'No puedes cambiar este pedido' using errcode = '42501';
  end if;
  return v_next;
end;
$$;

-- El vendedor cancela mientras el fotógrafo no va en camino
create or replace function public.cancel_service(p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.service_requests set status = 'cancelado'
   where id = p_request and seller_id = auth.uid() and status in ('pedido', 'aceptado');
  if not found then
    raise exception 'Ya no se puede cancelar este pedido' using errcode = 'P0001';
  end if;
end;
$$;

-- Pedidos libres cerca de mí, con la distancia (para la lista del fotógrafo)
create or replace function public.nearby_services()
returns table (id uuid, property_title text, city text, neighborhood text, scheduled_at timestamptz,
               notes text, distance_km numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, p.title, p.city, p.neighborhood, r.scheduled_at, r.notes,
         round(public.km_between(c.base_lat, c.base_lng, r.lat, r.lng)::numeric, 1)
  from public.service_requests r
  join public.properties p on p.id = r.property_id
  join public.creative_profiles c on c.id = auth.uid()
  where r.status = 'pedido' and r.scheduled_at > now()
    and c.specialty = 'fotografia' and c.base_lat is not null
    and public.km_between(c.base_lat, c.base_lng, r.lat, r.lng) <= c.service_radius_km
  order by r.scheduled_at;
$$;

revoke execute on function public.accept_service, public.advance_service, public.cancel_service,
  public.nearby_services, public.service_is_near_me from public, anon;
grant execute on function public.accept_service, public.advance_service, public.cancel_service,
  public.nearby_services, public.service_is_near_me to authenticated;

-- Avisos en tiempo real (Supabase Realtime respeta las políticas de arriba)
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.service_requests;
  end if;
end $$;
