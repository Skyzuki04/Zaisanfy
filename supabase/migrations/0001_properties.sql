-- Propiedades
create type public.property_status as enum ('draft', 'published', 'closed', 'hidden');

-- Tabla principal
create table public.properties (
  id          uuid primary key default gen_random_uuid(),
  seller_id   uuid not null references auth.users (id) on delete cascade,
  status      public.property_status not null default 'draft',
  data        jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint properties_data_is_object  check (jsonb_typeof(data) = 'object'),
  constraint properties_data_has_title  check (length(coalesce(data->>'title', '')) >= 3),
  constraint properties_data_has_price  check (case when jsonb_typeof(data->'price') = 'number' then (data->>'price')::numeric > 0 else false end),
  constraint properties_data_has_type   check (coalesce(data->>'propertyType' in ('casa', 'departamento', 'terreno', 'local', 'oficina'), false)),
  constraint properties_data_has_city   check (length(coalesce(data #>> '{location,city}', '')) >= 2)
);

comment on table  public.properties        is 'Inventario de propiedades (Fase 1). Columnas fijas + detalle flexible en data (JSONB).';
comment on column public.properties.data   is 'Detalle de la propiedad. Forma definida en packages/schemas (PropertyDataSchema).';

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger properties_set_updated_at
before update on public.properties
for each row execute function public.set_updated_at();

create index properties_seller_idx  on public.properties (seller_id);
create index properties_status_idx  on public.properties (status);
create index properties_price_idx   on public.properties (((data->>'price')::numeric));
create index properties_type_idx    on public.properties ((data->>'propertyType'));
create index properties_city_idx    on public.properties ((data #>> '{location,city}'));
create index properties_data_gin    on public.properties using gin (data jsonb_path_ops);

-- Seguridad: se activa RLS desde ahora.
alter table public.properties enable row level security;
