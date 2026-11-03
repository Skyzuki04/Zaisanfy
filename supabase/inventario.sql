-- =====================================================================
-- Inventario de la base de datos (SOLO LECTURA: no cambia nada)
-- Compara lo que hay en el esquema public con lo que crean las migraciones 0001-0007.
--   estado = 'OK'        -> existe y viene de una migración
--   estado = 'FALTA'     -> la migración lo crea pero no está en la base (falta correrla)
--   estado = 'SOBRA'     -> está en la base pero ninguna migración lo crea (revisar: prueba vieja o creado a mano)
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
-- =====================================================================
with esperado(tipo, nombre) as (
  values
    -- tablas
    ('tabla', 'properties'), ('tabla', 'profiles'), ('tabla', 'creative_profiles'),
    ('tabla', 'creative_posts'), ('tabla', 'bookmarks'), ('tabla', 'contact_requests'),
    -- tipos (enums)
    ('tipo', 'property_status'), ('tipo', 'user_role'), ('tipo', 'post_category'),
    ('tipo', 'contact_kind'), ('tipo', 'contact_status'),
    -- funciones
    ('funcion', 'set_updated_at'), ('funcion', 'handle_new_user'), ('funcion', 'my_role'),
    ('funcion', 'contact_requests_before_insert'), ('funcion', 'upgrade_role'),
    -- triggers
    ('trigger', 'properties.properties_set_updated_at'), ('trigger', 'profiles.profiles_set_updated_at'),
    ('trigger', 'creative_profiles.creative_profiles_set_updated_at'), ('trigger', 'creative_posts.creative_posts_set_updated_at'),
    ('trigger', 'contact_requests.contact_requests_set_updated_at'), ('trigger', 'contact_requests.contact_requests_before_insert')
),
real(tipo, nombre, detalle) as (
  select 'tabla', c.relname, 'RLS ' || case when c.relrowsecurity then 'activado' else 'APAGADO' end
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
  union all
  select 'vista', c.relname, 'vista'
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('v', 'm')
  union all
  select 'tipo', t.typname, string_agg(e.enumlabel, ', ' order by e.enumsortorder)
  from pg_type t join pg_namespace n on n.oid = t.typnamespace join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'public' group by t.typname
  union all
  select 'funcion', p.proname, case when p.prosecdef then 'security definer' else '' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') -- sin las de extensiones
  union all
  select 'trigger', c.relname || '.' || tg.tgname, ''
  from pg_trigger tg join pg_class c on c.oid = tg.tgrelid join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not tg.tgisinternal
)
select coalesce(r.tipo, e.tipo) as tipo,
       coalesce(r.nombre, e.nombre) as nombre,
       case when e.nombre is null then 'SOBRA' when r.nombre is null then 'FALTA' else 'OK' end as estado,
       coalesce(r.detalle, '') as detalle
from real r full join esperado e on e.tipo = r.tipo and e.nombre = r.nombre
union all
-- trigger que vive en auth.users (crea el perfil al registrarse)
select 'trigger', 'auth.users.on_auth_user_created',
       case when exists (select 1 from pg_trigger where tgname = 'on_auth_user_created') then 'OK' else 'FALTA' end, ''
union all
-- políticas RLS (solo informativo: cuántas tiene cada tabla)
select 'politicas', tablename, 'OK', count(*) || ' políticas: ' || string_agg(policyname, ' | ' order by policyname)
from pg_policies where schemaname = 'public' group by tablename
order by 3 desc, 1, 2;
