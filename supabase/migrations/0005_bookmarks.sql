-- =====================================================================
-- ZAI-31 · RF-VIS-04 · "Mi Lista" (propiedades guardadas)
-- - Cada usuario guarda propiedades publicadas en su lista.
-- - Nadie ve ni toca la lista de otra persona.
-- Requiere 0002_profiles_y_permisos.sql.
--
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
-- =====================================================================

create table public.bookmarks (
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  property_id  uuid not null references public.properties (id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (user_id, property_id)
);

comment on table public.bookmarks is 'Mi Lista: propiedades guardadas por cada usuario (ZAI-31).';

create index bookmarks_property_idx on public.bookmarks (property_id);

alter table public.bookmarks enable row level security;

create policy "Cada quien ve su lista"
on public.bookmarks for select to authenticated
using (user_id = (select auth.uid()));

create policy "Cada quien guarda en su lista propiedades publicadas"
on public.bookmarks for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.properties p where p.id = property_id and p.status = 'published')
);

create policy "Cada quien quita de su lista"
on public.bookmarks for delete to authenticated
using (user_id = (select auth.uid()));
