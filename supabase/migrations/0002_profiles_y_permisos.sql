-- =====================================================================
-- ZAI-20 · RNF-SEC-01 · Registro, inicio de sesión y permisos por rol
-- - Cada usuario de Supabase Auth tiene un perfil con su rol.
-- - El perfil se crea solo al registrarse (trigger en auth.users).
-- - Políticas RLS en properties:
--     visitante (sin sesión o con sesión) -> ve solo las publicadas
--     vendedor -> ve, crea, edita y borra SOLO sus propiedades
--     admin    -> ve y edita todo
-- Requiere 0001_properties.sql.
--
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
-- =====================================================================

-- 1) Roles de la plataforma (deben coincidir con UserRole en packages/schemas)
create type public.user_role as enum ('visitante', 'vendedor', 'creativo', 'admin');

-- 2) Perfil de cada usuario (1 a 1 con auth.users)
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        public.user_role not null default 'visitante',
  full_name   text check (full_name is null or length(full_name) between 2 and 120),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  public.profiles      is 'Perfil y rol de cada usuario (ZAI-20). Se crea solo al registrarse.';
comment on column public.profiles.role is 'visitante, vendedor, creativo o admin. El usuario no puede cambiarlo; solo un admin.';

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- 3) Al registrarse se crea el perfil.
--    La app manda el rol en options.data.role de supabase.auth.signUp().
--    Solo se aceptan visitante, vendedor o creativo: nadie se registra como admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested text := new.raw_user_meta_data->>'role';
begin
  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    case when requested in ('visitante', 'vendedor', 'creativo')
         then requested::public.user_role
         else 'visitante'::public.user_role end,
    nullif(trim(new.raw_user_meta_data->>'full_name'), '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- 4) Usuarios que ya existían (por ejemplo vendedor.demo@zaisanfy.test):
--    si ya tiene propiedades es vendedor; si no, visitante.
insert into public.profiles (id, role)
select u.id,
       case when exists (select 1 from public.properties p where p.seller_id = u.id)
            then 'vendedor'::public.user_role
            else 'visitante'::public.user_role end
from auth.users u
where not exists (select 1 from public.profiles pr where pr.id = u.id);

-- 5) Rol del usuario con sesión. security definer para que las políticas
--    puedan leer profiles sin chocar con el RLS de profiles.
create or replace function public.my_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- 6) El usuario puede cambiar su nombre, pero no su rol.
revoke update on public.profiles from anon, authenticated;
grant update (full_name) on public.profiles to authenticated;

-- 7) Políticas de profiles
alter table public.profiles enable row level security;

create policy "Cada quien ve su perfil"
on public.profiles for select to authenticated
using (id = (select auth.uid()));

create policy "Cada quien edita su perfil"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Admin ve y edita todos los perfiles"
on public.profiles for all to authenticated
using ((select public.my_role()) = 'admin')
with check ((select public.my_role()) = 'admin');

-- 8) Políticas de properties (RLS ya estaba activado en 0001)
create policy "Todos ven las propiedades publicadas"
on public.properties for select to anon, authenticated
using (status = 'published');

create policy "El vendedor ve sus propiedades"
on public.properties for select to authenticated
using (seller_id = (select auth.uid()));

create policy "El vendedor crea propiedades a su nombre"
on public.properties for insert to authenticated
with check (
  seller_id = (select auth.uid())
  and (select public.my_role()) = 'vendedor'
);

create policy "El vendedor edita sus propiedades"
on public.properties for update to authenticated
using (seller_id = (select auth.uid()))
with check (seller_id = (select auth.uid()));

create policy "El vendedor borra sus propiedades"
on public.properties for delete to authenticated
using (seller_id = (select auth.uid()));

create policy "Admin ve y edita todas las propiedades"
on public.properties for all to authenticated
using ((select public.my_role()) = 'admin')
with check ((select public.my_role()) = 'admin');
