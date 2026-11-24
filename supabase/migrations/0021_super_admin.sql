-- RF-ADM-01 a 03: panel del Super Admin dentro de la Consola.
-- 01 gestionar, suspender y "ver como" (solo lectura) a cualquier usuario.
-- 02 SEO/GEO Score de propiedades y publicaciones.
-- 03 MRR, churn y leads desbloqueados por mes.
-- Todo lo llama solo un admin; cada función lo revisa.

-- ===================== Suspensiones =====================
create table public.suspensions (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  reason       text check (reason is null or length(reason) <= 300),
  suspended_by uuid references auth.users (id) on delete set null,
  suspended_at timestamptz not null default now()
);

comment on table public.suspensions is 'RF-ADM-01: usuarios suspendidos. Su contenido deja de verse y no pueden escribir nada.';

alter table public.suspensions enable row level security;
revoke all on public.suspensions from anon, authenticated;
grant select on public.suspensions to authenticated;

create policy "Admin ve las suspensiones"
on public.suspensions for select to authenticated
using ((select public.my_role()) = 'admin');

create or replace function public.is_suspended(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user is not null and exists (select 1 from public.suspensions where user_id = p_user);
$$;

-- Para la Consola y el Escaparate: ¿mi cuenta está suspendida?
create or replace function public.am_suspended()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_suspended(auth.uid());
$$;

revoke execute on function public.is_suspended, public.am_suspended from public;
grant execute on function public.is_suspended, public.am_suspended to anon, authenticated;

-- Un suspendido no escribe nada (también bloquea las funciones que corren como dueño, porque los triggers siempre se disparan)
create or replace function public.block_suspended()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_suspended(auth.uid()) and coalesce(public.my_role()::text, '') <> 'admin' then
    raise exception 'Tu cuenta está suspendida. Escríbenos si crees que es un error.' using errcode = 'ZA007';
  end if;
  return coalesce(new, old);
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['properties', 'property_photos', 'creative_profiles', 'creative_posts', 'post_images',
                           'contact_requests', 'bookmarks', 'reports', 'service_requests', 'lead_unlocks', 'profiles']
  loop
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.block_suspended()',
                   t || '_block_suspended', t);
  end loop;
end $$;

-- El contenido de un suspendido no se ve en el Escaparate (el admin sí lo ve)
create policy "No se ve lo de usuarios suspendidos"
on public.properties as restrictive for select to anon, authenticated
using (not public.is_suspended(seller_id) or (select public.my_role()) = 'admin');

create policy "No se ven perfiles suspendidos"
on public.creative_profiles as restrictive for select to anon, authenticated
using (not public.is_suspended(id) or (select public.my_role()) = 'admin');

create policy "No se ven portafolios suspendidos"
on public.creative_posts as restrictive for select to anon, authenticated
using (not public.is_suspended(creative_id) or (select public.my_role()) = 'admin');

-- ===================== Usuarios =====================
create or replace function public.admin_users(p_search text default null)
returns table (id uuid, email text, full_name text, role public.user_role, plan text, created_at timestamptz,
               last_sign_in_at timestamptz, email_confirmed boolean, suspended boolean, suspended_reason text,
               properties bigint, posts bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin ve los usuarios' using errcode = '42501';
  end if;
  return query
  select u.id, u.email::text, p.full_name, p.role,
         coalesce(public.plan_of(u.id), 'freemium'),
         u.created_at, u.last_sign_in_at, u.email_confirmed_at is not null,
         s.user_id is not null, s.reason,
         (select count(*) from public.properties x where x.seller_id = u.id),
         (select count(*) from public.creative_posts x where x.creative_id = u.id)
  from auth.users u
  join public.profiles p on p.id = u.id
  left join public.suspensions s on s.user_id = u.id
  where p_search is null or p_search = ''
     or u.email ilike '%' || p_search || '%' or p.full_name ilike '%' || p_search || '%'
  order by u.created_at desc
  limit 200;
end;
$$;

create or replace function public.admin_set_suspended(p_user uuid, p_suspend boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin suspende usuarios' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'No te puedes suspender a ti mismo' using errcode = 'P0001';
  end if;
  if (select role from public.profiles where id = p_user) = 'admin' then
    raise exception 'No se puede suspender a otro admin' using errcode = 'P0001';
  end if;
  if p_suspend then
    insert into public.suspensions (user_id, reason, suspended_by) values (p_user, nullif(trim(p_reason), ''), auth.uid())
    on conflict (user_id) do update set reason = excluded.reason, suspended_by = excluded.suspended_by, suspended_at = now();
  else
    delete from public.suspensions where user_id = p_user;
  end if;
end;
$$;

create or replace function public.admin_set_role(p_user uuid, p_role public.user_role)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin cambia roles' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'No puedes cambiar tu propio rol' using errcode = 'P0001';
  end if;
  update public.profiles set role = p_role where id = p_user;
end;
$$;

-- "Ver como" (solo lectura): todo lo que ese usuario ve de su cuenta, sin entrar como él
create or replace function public.admin_user_detail(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin ve el detalle de usuarios' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'plan', coalesce(public.plan_of(p_user), 'freemium'),
    'credits', coalesce((select sum(amount) from public.credit_movements where user_id = p_user), 0),
    'paid_mxn', coalesce((select sum(amount_mxn) from public.payments where user_id = p_user and status = 'pagado'), 0),
    'properties', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'status', status, 'city', city, 'price', price)
                                             order by created_at desc)
                            from public.properties where seller_id = p_user), '[]'),
    'posts', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'hidden', hidden) order by created_at desc)
                       from public.creative_posts where creative_id = p_user), '[]'),
    'requests_sent', (select count(*) from public.contact_requests where requester_id = p_user),
    'requests_received', (select count(*) from public.contact_requests r
                          where public.request_recipient(r.property_id, r.creative_id, r.post_id) = p_user),
    'reports_against', (select count(*) from public.reports r
                        left join public.properties p on p.id = r.property_id
                        left join public.creative_posts c on c.id = r.post_id
                        where coalesce(p.seller_id, c.creative_id) = p_user)
  );
end;
$$;

-- ===================== SEO/GEO Score =====================
-- 100 puntos. Cada consejo dice qué subir de calificación.
create or replace function public.admin_seo_scores()
returns table (kind text, id uuid, title text, owner_name text, status text, score integer, tips text[])
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin ve el SEO Score' using errcode = '42501';
  end if;
  return query
  with p as (
    select pr.id, pr.title, pf.full_name, pr.status::text as status,
           length(pr.title) as tl, length(coalesce(pr.description, '')) as dl,
           (select count(*) from public.property_photos f where f.property_id = pr.id and f.kind = 'foto') as fotos,
           exists (select 1 from public.property_photos f where f.property_id = pr.id and f.kind = 'panorama') as pano,
           pr.lat is not null and pr.lng is not null as geo,
           coalesce(pr.neighborhood, pr.address) is not null as barrio,
           pr.area_m2 is not null as area
    from public.properties pr join public.profiles pf on pf.id = pr.seller_id
    where pr.status <> 'draft'
  ), c as (
    select cp.id, cp.title, cr.display_name, case when cp.hidden then 'hidden' else 'published' end as status,
           length(cp.title) as tl, length(coalesce(cp.description, '')) as dl,
           (select count(*) from public.post_images i where i.post_id = cp.id) as imgs,
           cp.city is not null as ciudad, cp.property_type is not null as tipo
    from public.creative_posts cp join public.creative_profiles cr on cr.id = cp.creative_id
  )
  select 'propiedad', p.id, p.title, p.full_name, p.status,
         (case when p.tl between 30 and 80 then 15 when p.tl >= 10 then 7 else 0 end
          + case when p.dl >= 300 then 20 when p.dl >= 100 then 10 else 0 end
          + case when p.fotos >= 8 then 15 when p.fotos >= 3 then 8 else 0 end
          + case when p.pano then 15 else 0 end
          + case when p.geo then 15 else 0 end
          + case when p.barrio then 5 else 0 end
          + case when p.area then 5 else 0 end
          + 10)::integer,
         array_remove(array[
           case when p.tl not between 30 and 80 then 'Título de 30 a 80 letras' end,
           case when p.dl < 300 then 'Descripción de al menos 300 letras' end,
           case when p.fotos < 8 then 'Al menos 8 fotos' end,
           case when not p.pano then 'Foto 360°' end,
           case when not p.geo then 'Ubicación en el mapa (GEO)' end,
           case when not p.barrio then 'Colonia o dirección' end,
           case when not p.area then 'Metros cuadrados' end], null)
  from p
  union all
  select 'publicacion', c.id, c.title, c.display_name, c.status,
         (case when c.tl between 15 and 80 then 20 when c.tl >= 5 then 10 else 0 end
          + case when c.dl >= 150 then 25 when c.dl >= 50 then 12 else 0 end
          + case when c.imgs >= 3 then 25 when c.imgs >= 1 then 12 else 0 end
          + case when c.ciudad then 15 else 0 end
          + case when c.tipo then 15 else 0 end)::integer,
         array_remove(array[
           case when c.tl not between 15 and 80 then 'Título de 15 a 80 letras' end,
           case when c.dl < 150 then 'Descripción de al menos 150 letras' end,
           case when c.imgs < 3 then 'Al menos 3 imágenes' end,
           case when not c.ciudad then 'Ciudad (GEO)' end,
           case when not c.tipo then 'Tipo de propiedad' end], null)
  from c
  order by 6, 3;
end;
$$;

-- ===================== Métricas =====================
-- Suscripción viva en una fecha: ya existía y no estaba cancelada todavía. Las de prueba e incompletas no cuentan.
-- Un cambio de plan (cancela una y abre otra el mismo día) no cuenta como churn.
create or replace function public.admin_metrics(p_months integer default 6)
returns table (month date, mrr numeric, active_subs bigint, new_subs bigint, churned bigint, churn_pct numeric,
               leads_unlocked bigint, leads_by_credit bigint, leads_by_payment bigint, revenue numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin ve las métricas' using errcode = '42501';
  end if;
  return query
  with months as (
    select (date_trunc('month', now() at time zone 'America/Mexico_City') - make_interval(months => g))::date as m
    from generate_series(0, greatest(p_months, 1) - 1) g
  ), subs as (
    select s.*, pl.price_mxn,
           case when s.status = 'cancelada' then s.updated_at end as ended_at,
           s.status = 'cancelada' and not exists (
             select 1 from public.subscriptions s2
             where s2.user_id = s.user_id and s2.id <> s.id and s2.created_at between s.updated_at - interval '1 day' and s.updated_at + interval '1 day'
           ) as is_churn
    from public.subscriptions s join public.plans pl on pl.id = s.plan_id
    where s.status in ('activa', 'pago_vencido', 'cancelada') and pl.price_mxn > 0
  )
  select mo.m,
         coalesce((select sum(x.price_mxn) from subs x
                   where x.created_at < (mo.m + interval '1 month') and (x.ended_at is null or x.ended_at >= (mo.m + interval '1 month'))), 0),
         (select count(*) from subs x
          where x.created_at < (mo.m + interval '1 month') and (x.ended_at is null or x.ended_at >= (mo.m + interval '1 month'))),
         (select count(*) from subs x where x.created_at >= mo.m and x.created_at < mo.m + interval '1 month'),
         (select count(*) from subs x where x.is_churn and x.ended_at >= mo.m and x.ended_at < mo.m + interval '1 month'),
         round(100.0 * (select count(*) from subs x where x.is_churn and x.ended_at >= mo.m and x.ended_at < mo.m + interval '1 month')
               / nullif((select count(*) from subs x where x.created_at < mo.m and (x.ended_at is null or x.ended_at >= mo.m)), 0), 1),
         (select count(*) from public.lead_unlocks l where l.unlocked_at >= mo.m and l.unlocked_at < mo.m + interval '1 month'),
         (select count(*) from public.lead_unlocks l where l.credit_movement_id is not null and l.unlocked_at >= mo.m and l.unlocked_at < mo.m + interval '1 month'),
         (select count(*) from public.lead_unlocks l where l.payment_id is not null and l.unlocked_at >= mo.m and l.unlocked_at < mo.m + interval '1 month'),
         coalesce((select sum(y.amount_mxn) from public.payments y
                   where y.status = 'pagado' and y.created_at >= mo.m and y.created_at < mo.m + interval '1 month'), 0)
  from months mo
  order by mo.m desc;
end;
$$;

revoke execute on function public.admin_users, public.admin_set_suspended, public.admin_set_role, public.admin_user_detail,
  public.admin_seo_scores, public.admin_metrics from public, anon;
grant execute on function public.admin_users, public.admin_set_suspended, public.admin_set_role, public.admin_user_detail,
  public.admin_seo_scores, public.admin_metrics to authenticated;
