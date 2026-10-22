-- =====================================================================
-- ZAI-28 · RF-CRE-01 · Portafolio del creativo (renders, planos e ideas)
-- - Cada publicación pertenece a un perfil de creativo.
-- - Las imágenes viven en Cloudinary; aquí solo se guardan las URLs.
-- - property_type y city son opcionales y sirven para sugerir diseños en
--   el detalle de una propiedad (ZAI-30).
-- - Todos ven el portafolio; solo el dueño crea, edita y borra.
-- Requiere 0003_creative_profiles.sql.
--
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
-- =====================================================================

create type public.post_category as enum ('render', 'plano', 'idea');

create table public.creative_posts (
  id             uuid primary key default gen_random_uuid(),
  creative_id    uuid not null references public.creative_profiles (id) on delete cascade,
  title          text not null check (length(trim(title)) between 3 and 120),
  description    text check (description is null or length(description) <= 2000),
  category       public.post_category not null,
  images         text[] not null check (cardinality(images) between 1 and 10),
  property_type  text check (property_type is null or property_type in ('casa', 'departamento', 'terreno', 'local', 'oficina')),
  city           text check (city is null or length(city) between 2 and 80),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.creative_posts is 'Portafolio de los creativos (ZAI-28). Se muestra en su perfil, en el muro (ZAI-29) y como inspiración (ZAI-30).';

create trigger creative_posts_set_updated_at
before update on public.creative_posts
for each row execute function public.set_updated_at();

-- Índices para el perfil, el muro (recientes y por categoría) y las sugerencias
create index creative_posts_creative_idx  on public.creative_posts (creative_id, created_at desc);
create index creative_posts_recent_idx    on public.creative_posts (created_at desc);
create index creative_posts_category_idx  on public.creative_posts (category, created_at desc);
create index creative_posts_type_idx      on public.creative_posts (property_type);
create index creative_posts_city_idx      on public.creative_posts (lower(city));

alter table public.creative_posts enable row level security;

create policy "Todos ven los portafolios"
on public.creative_posts for select to anon, authenticated
using (true);

create policy "El creativo publica en su portafolio"
on public.creative_posts for insert to authenticated
with check (creative_id = (select auth.uid()));

create policy "El creativo edita su portafolio"
on public.creative_posts for update to authenticated
using (creative_id = (select auth.uid()))
with check (creative_id = (select auth.uid()));

create policy "El creativo borra de su portafolio"
on public.creative_posts for delete to authenticated
using (creative_id = (select auth.uid()));

create policy "Admin ve y edita todos los portafolios"
on public.creative_posts for all to authenticated
using ((select public.my_role()) = 'admin')
with check ((select public.my_role()) = 'admin');
