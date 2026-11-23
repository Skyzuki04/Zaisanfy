-- ZAI-33 (tareas antitrolls): botón "Reportar" en propiedades y publicaciones.
-- Cualquiera con cuenta confirmada reporta; el admin revisa y oculta o descarta.
-- Una propiedad oculta pasa a status 'hidden'; una publicación oculta queda con hidden = true.

create type public.report_reason as enum ('fraude', 'datos_falsos', 'contenido_inapropiado', 'spam', 'otro');
create type public.report_status as enum ('abierto', 'oculto', 'descartado');

-- Publicaciones ocultas por el admin
alter table public.creative_posts add column hidden boolean not null default false;
comment on column public.creative_posts.hidden is 'true = ocultada por el admin tras un reporte. Solo la ven su creativo y el admin.';

drop policy "Todos ven los portafolios" on public.creative_posts;
create policy "Todos ven los portafolios"
on public.creative_posts for select to anon, authenticated
using (not hidden or creative_id = (select auth.uid()));

-- El creativo no se puede "des-ocultar" solo
create or replace function public.creative_posts_keep_hidden()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.hidden is distinct from old.hidden and coalesce(public.my_role()::text, '') <> 'admin'
     and current_user not in ('postgres', 'service_role') then
    new.hidden := old.hidden;
  end if;
  return new;
end;
$$;

create trigger creative_posts_keep_hidden
before update on public.creative_posts
for each row execute function public.creative_posts_keep_hidden();

create table public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  property_id  uuid references public.properties (id) on delete cascade,
  post_id      uuid references public.creative_posts (id) on delete cascade,
  reason       public.report_reason not null,
  details      text check (details is null or length(details) <= 500),
  status       public.report_status not null default 'abierto',
  resolved_by  uuid references auth.users (id) on delete set null,
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  constraint reports_un_destino check (num_nonnulls(property_id, post_id) = 1)
);

comment on table public.reports is 'ZAI-33: reportes de propiedades o publicaciones. Solo uno de property_id / post_id va lleno.';

create unique index reports_once_property on public.reports (reporter_id, property_id) where property_id is not null;
create unique index reports_once_post on public.reports (reporter_id, post_id) where post_id is not null;
create index reports_open_idx on public.reports (status, created_at desc);

create or replace function public.reports_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  new.reporter_id := auth.uid();
  if new.reporter_id is null then
    raise exception 'Inicia sesión para reportar' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = new.reporter_id and email_confirmed_at is not null) then
    raise exception 'Confirma tu correo antes de reportar' using errcode = 'P0001';
  end if;
  v_owner := coalesce((select seller_id from public.properties where id = new.property_id),
                      (select creative_id from public.creative_posts where id = new.post_id));
  if v_owner is null then
    raise exception 'Esto ya no existe' using errcode = 'P0001';
  end if;
  if v_owner = new.reporter_id then
    raise exception 'No puedes reportar algo tuyo' using errcode = 'P0001';
  end if;
  if (select count(*) from public.reports where reporter_id = new.reporter_id and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'Llegaste al límite de 10 reportes por día' using errcode = 'P0001';
  end if;
  new.status := 'abierto';
  new.resolved_by := null;
  new.resolved_at := null;
  new.created_at := now();
  return new;
end;
$$;

create trigger reports_before_insert
before insert on public.reports
for each row execute function public.reports_before_insert();

revoke all on public.reports from anon;
revoke update, delete on public.reports from authenticated;
alter table public.reports enable row level security;

create policy "Cualquiera con cuenta reporta"
on public.reports for insert to authenticated
with check (reporter_id = (select auth.uid()));

create policy "Cada quien ve sus reportes"
on public.reports for select to authenticated
using (reporter_id = (select auth.uid()));

create policy "Admin ve todos los reportes"
on public.reports for select to authenticated
using ((select public.my_role()) = 'admin');

-- Bandeja del admin: un renglón por cosa reportada, con cuántos reportes tiene
create or replace function public.admin_reports()
returns table (target text, target_id uuid, title text, owner_name text, reports bigint,
               reasons text, last_details text, last_at timestamptz, is_hidden boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select case when r.property_id is not null then 'propiedad' else 'publicacion' end,
         coalesce(r.property_id, r.post_id),
         coalesce(p.title, cp.title),
         coalesce(pr.full_name, c.display_name),
         count(*),
         string_agg(distinct r.reason::text, ', '),
         (array_agg(r.details order by r.created_at desc) filter (where r.details is not null))[1],
         max(r.created_at),
         coalesce(p.status = 'hidden', cp.hidden, false)
  from public.reports r
  left join public.properties p on p.id = r.property_id
  left join public.profiles pr on pr.id = p.seller_id
  left join public.creative_posts cp on cp.id = r.post_id
  left join public.creative_profiles c on c.id = cp.creative_id
  where r.status = 'abierto' and public.my_role() = 'admin'
  group by 1, 2, 3, 4, p.status, cp.hidden
  order by count(*) desc, max(r.created_at) desc;
$$;

-- El admin oculta o descarta. Cierra todos los reportes abiertos de esa cosa.
create or replace function public.resolve_report(p_target text, p_target_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin revisa reportes' using errcode = '42501';
  end if;
  if p_action not in ('ocultar', 'descartar') or p_target not in ('propiedad', 'publicacion') then
    raise exception 'Acción inválida' using errcode = 'P0001';
  end if;
  if p_action = 'ocultar' then
    if p_target = 'propiedad' then
      update public.properties set status = 'hidden' where id = p_target_id;
    else
      update public.creative_posts set hidden = true where id = p_target_id;
    end if;
  end if;
  update public.reports
     set status = case p_action when 'ocultar' then 'oculto'::public.report_status else 'descartado'::public.report_status end,
         resolved_by = auth.uid(), resolved_at = now()
   where status = 'abierto'
     and ((p_target = 'propiedad' and property_id = p_target_id) or (p_target = 'publicacion' and post_id = p_target_id));
end;
$$;

revoke execute on function public.admin_reports, public.resolve_report from public, anon;
grant execute on function public.admin_reports, public.resolve_report to authenticated;

-- Una propiedad que el admin ocultó por reporte no la puede volver a publicar el vendedor
create or replace function public.properties_keep_hidden()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'hidden' and new.status <> 'hidden'
     and coalesce(public.my_role()::text, '') <> 'admin'
     and exists (select 1 from public.reports where property_id = new.id and status = 'oculto') then
    raise exception 'Esta propiedad la ocultó el equipo de Zaisanfy por un reporte. Escríbenos para revisarla.'
      using errcode = 'ZA005';
  end if;
  return new;
end;
$$;

create trigger properties_keep_hidden
before update of status on public.properties
for each row execute function public.properties_keep_hidden();
