-- =====================================================================
-- ZAI-27 · RF-CRE-01 · Perfil público del creativo
-- - Un perfil por creativo (mismo id que su usuario).
-- - Cualquiera puede ver los perfiles (son públicos).
-- - Solo el dueño, con rol creativo, puede crearlo, editarlo o borrarlo.
-- Requiere 0002_profiles_y_permisos.sql.
--
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
-- =====================================================================

create table public.creative_profiles (
  id            uuid primary key references public.profiles (id) on delete cascade,
  display_name  text not null check (length(trim(display_name)) between 2 and 80),
  specialty     text not null default 'otro'
                check (specialty in ('arquitectura', 'render3d', 'interiorismo', 'fotografia', 'otro')),
  bio           text check (bio is null or length(bio) <= 1000),
  city          text check (city is null or length(city) between 2 and 80),
  state         text check (state is null or length(state) between 2 and 80),
  avatar_url    text check (avatar_url is null or avatar_url ~ '^https?://'),
  website       text check (website is null or website ~ '^https?://'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.creative_profiles is 'Perfil público de arquitectos y artistas 3D (ZAI-27).';

create trigger creative_profiles_set_updated_at
before update on public.creative_profiles
for each row execute function public.set_updated_at();

alter table public.creative_profiles enable row level security;

create policy "Todos ven los perfiles de creativos"
on public.creative_profiles for select to anon, authenticated
using (true);

create policy "El creativo crea su perfil"
on public.creative_profiles for insert to authenticated
with check (id = (select auth.uid()) and (select public.my_role()) = 'creativo');

create policy "El creativo edita su perfil"
on public.creative_profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "El creativo borra su perfil"
on public.creative_profiles for delete to authenticated
using (id = (select auth.uid()));

create policy "Admin ve y edita todos los perfiles de creativos"
on public.creative_profiles for all to authenticated
using ((select public.my_role()) = 'admin')
with check ((select public.my_role()) = 'admin');
