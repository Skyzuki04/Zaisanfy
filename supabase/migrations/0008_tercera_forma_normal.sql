-- Modelo en 3FN

-- Propiedades en columnas
alter table public.properties
  add column title         text,
  add column description   text,
  add column operation     text,
  add column property_type text,
  add column price         numeric(14, 2),
  add column currency      text not null default 'MXN',
  add column bedrooms      integer not null default 0,
  add column bathrooms     numeric(4, 1) not null default 0,
  add column area_m2       numeric(10, 2),
  add column state         text,
  add column city          text,
  add column neighborhood  text,
  add column address       text,
  add column lat           double precision,
  add column lng           double precision;

update public.properties set
  title         = data->>'title',
  description   = nullif(trim(data->>'description'), ''),
  operation     = coalesce(nullif(data->>'operation', ''), 'venta'),
  property_type = data->>'propertyType',
  price         = (data->>'price')::numeric,
  currency      = coalesce(nullif(data->>'currency', ''), 'MXN'),
  bedrooms      = coalesce(round((data->>'bedrooms')::numeric), 0),
  bathrooms     = coalesce((data->>'bathrooms')::numeric, 0),
  area_m2       = nullif((data->>'areaM2')::numeric, 0),
  state         = coalesce(nullif(trim(data #>> '{location,state}'), ''), 'Sin estado'),
  city          = trim(data #>> '{location,city}'),
  neighborhood  = nullif(trim(data #>> '{location,neighborhood}'), ''),
  address       = nullif(trim(data #>> '{location,address}'), ''),
  lat           = (data #>> '{location,lat}')::double precision,
  lng           = (data #>> '{location,lng}')::double precision;

alter table public.properties
  alter column title set not null,
  alter column operation set not null,
  alter column property_type set not null,
  alter column price set not null,
  alter column state set not null,
  alter column city set not null,
  add constraint properties_title_len     check (length(trim(title)) between 3 and 120),
  add constraint properties_desc_len      check (description is null or length(description) <= 2000),
  add constraint properties_operation     check (operation in ('venta', 'renta')),
  add constraint properties_type          check (property_type in ('casa', 'departamento', 'terreno', 'local', 'oficina')),
  add constraint properties_price         check (price > 0),
  add constraint properties_currency      check (currency in ('MXN', 'USD')),
  add constraint properties_bedrooms      check (bedrooms >= 0),
  add constraint properties_bathrooms     check (bathrooms >= 0),
  add constraint properties_area          check (area_m2 is null or area_m2 > 0),
  add constraint properties_state_len     check (length(trim(state)) >= 2),
  add constraint properties_city_len      check (length(trim(city)) >= 2),
  add constraint properties_neighborhood  check (neighborhood is null or length(trim(neighborhood)) >= 2),
  add constraint properties_lat           check (lat is null or lat between -90 and 90),
  add constraint properties_lng           check (lng is null or lng between -180 and 180);

-- Fotos (posición 0 = portada) y 360
create type public.photo_kind as enum ('foto', 'panorama');

create table public.property_photos (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  kind         public.photo_kind not null default 'foto',
  url          text not null check (url ~ '^https?://'),
  position     smallint not null default 0 check (position between 0 and 29),
  created_at   timestamptz not null default now(),
  unique (property_id, kind, position)
);

create unique index property_photos_one_panorama on public.property_photos (property_id) where kind = 'panorama';

comment on table public.property_photos is 'Fotos de la galería (kind foto, la posición 0 es la portada) y la foto 360 (kind panorama).';

with src as (
  select p.id, x.url, x.o
  from public.properties p
  cross join lateral (
    select p.data #>> '{media,coverUrl}' as url, 0::bigint as o
    union all
    select g.url, g.o
    from jsonb_array_elements_text(coalesce(p.data #> '{media,gallery}', '[]'::jsonb)) with ordinality as g (url, o)
  ) as x
  where coalesce(x.url, '') ~ '^https?://'
), dedup as (
  select id, url, min(o) as o from src group by id, url
), ranked as (
  select id, url, row_number() over (partition by id order by o) - 1 as pos from dedup
)
insert into public.property_photos (property_id, kind, url, position)
select id, 'foto', url, pos from ranked where pos <= 29;

insert into public.property_photos (property_id, kind, url, position)
select id, 'panorama', data #>> '{media,panorama360Url}', 0
from public.properties
where coalesce(data #>> '{media,panorama360Url}', '') ~ '^https?://';

alter table public.properties drop column data;

comment on table public.properties is 'Inventario de propiedades. Las fotos viven en property_photos.';

create index properties_price_idx on public.properties (price);
create index properties_type_idx  on public.properties (property_type);
create index properties_op_idx    on public.properties (operation);
create index properties_city_idx  on public.properties (lower(city));

alter table public.property_photos enable row level security;

create policy "Las fotos se ven igual que su propiedad"
on public.property_photos for select to anon, authenticated
using (exists (select 1 from public.properties p where p.id = property_id));

create policy "El vendedor maneja las fotos de sus propiedades"
on public.property_photos for all to authenticated
using (exists (select 1 from public.properties p where p.id = property_id and p.seller_id = (select auth.uid())))
with check (exists (select 1 from public.properties p where p.id = property_id and p.seller_id = (select auth.uid())));

create policy "Admin maneja todas las fotos"
on public.property_photos for all to authenticated
using ((select public.my_role()) = 'admin')
with check ((select public.my_role()) = 'admin');

-- Imágenes del portafolio
create table public.post_images (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.creative_posts (id) on delete cascade,
  url         text not null check (url ~ '^https?://'),
  position    smallint not null default 0 check (position between 0 and 9),
  created_at  timestamptz not null default now(),
  unique (post_id, position)
);

comment on table public.post_images is 'Imágenes de cada publicación del portafolio, en orden. La posición 0 es la portada.';

insert into public.post_images (post_id, url, position)
select cp.id, i.url, (i.o - 1)::smallint
from public.creative_posts cp
cross join lateral unnest(cp.images) with ordinality as i (url, o)
where i.o <= 10 and i.url ~ '^https?://';

alter table public.creative_posts drop column images;

alter table public.post_images enable row level security;

create policy "Todos ven las imágenes del portafolio"
on public.post_images for select to anon, authenticated
using (true);

create policy "El creativo maneja las imágenes de sus publicaciones"
on public.post_images for all to authenticated
using (exists (select 1 from public.creative_posts cp where cp.id = post_id and cp.creative_id = (select auth.uid())))
with check (exists (select 1 from public.creative_posts cp where cp.id = post_id and cp.creative_id = (select auth.uid())));

create policy "Admin maneja todas las imágenes"
on public.post_images for all to authenticated
using ((select public.my_role()) = 'admin')
with check ((select public.my_role()) = 'admin');

-- Guardar fila y fotos juntas
create or replace function public.save_property(
  p_id uuid, p_title text, p_description text, p_operation text, p_property_type text,
  p_price numeric, p_currency text, p_bedrooms integer, p_bathrooms numeric, p_area_m2 numeric,
  p_state text, p_city text, p_neighborhood text, p_address text, p_lat double precision, p_lng double precision,
  p_photos text[], p_panorama text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if coalesce(cardinality(p_photos), 0) > 30 then
    raise exception 'Máximo 30 fotos' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.properties (seller_id, status, title, description, operation, property_type, price, currency,
                                   bedrooms, bathrooms, area_m2, state, city, neighborhood, address, lat, lng)
    values (auth.uid(), 'draft', p_title, p_description, p_operation, p_property_type, p_price, coalesce(p_currency, 'MXN'),
            coalesce(p_bedrooms, 0), coalesce(p_bathrooms, 0), p_area_m2, p_state, p_city, p_neighborhood, p_address, p_lat, p_lng)
    returning id into v_id;
  else
    update public.properties set
      title = p_title, description = p_description, operation = p_operation, property_type = p_property_type,
      price = p_price, currency = coalesce(p_currency, 'MXN'), bedrooms = coalesce(p_bedrooms, 0),
      bathrooms = coalesce(p_bathrooms, 0), area_m2 = p_area_m2, state = p_state, city = p_city,
      neighborhood = p_neighborhood, address = p_address, lat = p_lat, lng = p_lng
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'No encontramos esta propiedad o no es tuya' using errcode = '42501';
    end if;
    delete from public.property_photos where property_id = v_id;
  end if;

  insert into public.property_photos (property_id, kind, url, position)
  select v_id, 'foto', u, (o - 1)::smallint
  from unnest(coalesce(p_photos, '{}')) with ordinality as t (u, o);

  if nullif(p_panorama, '') is not null then
    insert into public.property_photos (property_id, kind, url, position) values (v_id, 'panorama', p_panorama, 0);
  end if;

  return v_id;
end;
$$;

create or replace function public.save_post(
  p_id uuid, p_title text, p_description text, p_category public.post_category,
  p_property_type text, p_city text, p_images text[]
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if coalesce(cardinality(p_images), 0) not between 1 and 10 then
    raise exception 'Sube de 1 a 10 imágenes' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.creative_posts (creative_id, title, description, category, property_type, city)
    values (auth.uid(), p_title, p_description, p_category, p_property_type, p_city)
    returning id into v_id;
  else
    update public.creative_posts set
      title = p_title, description = p_description, category = p_category,
      property_type = p_property_type, city = p_city
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'No encontramos esta publicación o no es tuya' using errcode = '42501';
    end if;
    delete from public.post_images where post_id = v_id;
  end if;

  insert into public.post_images (post_id, url, position)
  select v_id, u, (o - 1)::smallint
  from unnest(p_images) with ordinality as t (u, o);

  return v_id;
end;
$$;

revoke execute on function public.save_property from public, anon;
revoke execute on function public.save_post from public, anon;
grant execute on function public.save_property to authenticated;
grant execute on function public.save_post to authenticated;

-- Solicitudes sin datos copiados
drop policy "El cliente y quien la recibe ven la solicitud" on public.contact_requests;
drop policy "Quien la recibe cambia el estado" on public.contact_requests;

alter table public.contact_requests drop constraint contact_requests_check;

update public.contact_requests set creative_id = null where post_id is not null;

alter table public.contact_requests
  drop column kind,
  drop column recipient_id,
  drop column requester_name,
  drop column requester_email,
  add constraint contact_requests_un_destino check (num_nonnulls(property_id, creative_id, post_id) = 1);

alter table public.contact_requests drop constraint contact_requests_post_id_fkey;
alter table public.contact_requests
  add constraint contact_requests_post_id_fkey foreign key (post_id) references public.creative_posts (id) on delete cascade;

drop type public.contact_kind;

create index contact_requests_property_idx on public.contact_requests (property_id);
create index contact_requests_creative_idx on public.contact_requests (creative_id);
create index contact_requests_post_idx     on public.contact_requests (post_id);

comment on table public.contact_requests is 'Solicitudes de visita (property_id) y de cotización (creative_id o post_id). Solo uno de los tres va lleno.';

-- Quién recibe la solicitud
create or replace function public.request_recipient(p_property uuid, p_creative uuid, p_post uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select seller_id from public.properties where id = p_property),
    p_creative,
    (select creative_id from public.creative_posts where id = p_post)
  );
$$;

-- Tipo calculado (select "*, kind")
create or replace function public.kind(r public.contact_requests)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when r.property_id is not null then 'visita' else 'cotizacion' end;
$$;

create or replace function public.contact_requests_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
  v_status    text;
  v_creative  uuid;
begin
  new.requester_id := auth.uid();
  if new.requester_id is null then
    raise exception 'Inicia sesión para enviar una solicitud' using errcode = '42501';
  end if;

  if not exists (select 1 from auth.users where id = new.requester_id and email_confirmed_at is not null) then
    raise exception 'Confirma tu correo antes de enviar solicitudes' using errcode = 'P0001';
  end if;

  if new.property_id is not null then
    select p.seller_id, p.status::text into v_recipient, v_status
    from public.properties p where p.id = new.property_id;
    if v_recipient is null or v_status <> 'published' then
      raise exception 'Esta propiedad ya no está disponible' using errcode = 'P0001';
    end if;
    new.creative_id := null;
    new.post_id := null;
  else
    if new.post_id is not null then
      select cp.creative_id into v_creative from public.creative_posts cp where cp.id = new.post_id;
      if v_creative is null or (new.creative_id is not null and v_creative <> new.creative_id) then
        new.post_id := null;
      else
        new.creative_id := null;
      end if;
    end if;
    v_creative := coalesce(v_creative, new.creative_id);
    if new.post_id is null then
      new.creative_id := v_creative;
    end if;
    select c.id into v_recipient from public.creative_profiles c where c.id = v_creative;
    if v_recipient is null then
      raise exception 'Este creativo ya no está disponible' using errcode = 'P0001';
    end if;
    new.operation := null;
  end if;

  if v_recipient = new.requester_id then
    raise exception 'No puedes enviarte una solicitud a ti mismo' using errcode = 'P0001';
  end if;

  if (select count(*) from public.contact_requests r
      where r.requester_id = new.requester_id and r.created_at > now() - interval '24 hours') >= 5 then
    raise exception 'Llegaste al límite de 5 solicitudes por día. Intenta de nuevo mañana' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.contact_requests r
             where r.requester_id = new.requester_id and r.status <> 'cerrada'
               and public.request_recipient(r.property_id, r.creative_id, r.post_id) = v_recipient
               and (r.property_id = new.property_id or (new.property_id is null and r.property_id is null))) then
    raise exception 'Ya tienes una solicitud abierta aquí. Te contactarán pronto' using errcode = 'P0001';
  end if;

  new.status := 'nueva';
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

create policy "El cliente y quien la recibe ven la solicitud"
on public.contact_requests for select to authenticated
using (
  requester_id = (select auth.uid())
  or public.request_recipient(property_id, creative_id, post_id) = (select auth.uid())
);

create policy "Quien la recibe cambia el estado"
on public.contact_requests for update to authenticated
using (public.request_recipient(property_id, creative_id, post_id) = (select auth.uid()))
with check (public.request_recipient(property_id, creative_id, post_id) = (select auth.uid()));

-- Bandeja de quien recibe
create or replace function public.my_inbox()
returns table (
  id uuid, kind text, property_id uuid, property_title text, creative_id uuid, post_id uuid, post_title text,
  requester_name text, requester_email text, phone text, operation text, preferred_times text, message text,
  status public.contact_status, created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, public.kind(r), r.property_id, p.title, r.creative_id, r.post_id, cp.title,
         coalesce(pr.full_name, split_part(u.email, '@', 1)), u.email,
         r.phone, r.operation, r.preferred_times, r.message, r.status, r.created_at
  from public.contact_requests r
  join auth.users u on u.id = r.requester_id
  left join public.profiles pr on pr.id = r.requester_id
  left join public.properties p on p.id = r.property_id
  left join public.creative_posts cp on cp.id = r.post_id
  where auth.uid() is not null
    and public.request_recipient(r.property_id, r.creative_id, r.post_id) = auth.uid()
  order by r.created_at desc;
$$;

revoke execute on function public.my_inbox from public, anon;
grant execute on function public.my_inbox to authenticated;
revoke execute on function public.request_recipient from public, anon;
grant execute on function public.request_recipient to authenticated;
