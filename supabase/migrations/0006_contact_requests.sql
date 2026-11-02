-- =====================================================================
-- ZAI-33 (versión básica) · Contacto con el vendedor y cotización con el creativo
-- - El cliente con sesión pide una visita a una propiedad publicada
--   o una cotización a un creativo.
-- - La solicitud le llega al vendedor o al creativo (recipient_id), que la ve en la Consola
--   y le cambia el estado: nueva -> contactado -> agendada -> cerrada.
-- - La base de datos decide quién la recibe y copia el nombre y el correo del cliente:
--   no se confía en lo que mande la app.
-- - Candados: correo confirmado, máximo 5 solicitudes en 24 h, una sola abierta
--   por propiedad (o por creativo) y nadie se contacta a sí mismo.
-- Requiere 0002 a 0004.
--
-- Cómo usarlo: Supabase > SQL Editor > New query > pegar todo > Run.
-- =====================================================================

-- 1) Tipos (deben coincidir con ContactKind y ContactStatus en packages/schemas)
create type public.contact_kind as enum ('visita', 'cotizacion');
create type public.contact_status as enum ('nueva', 'contactado', 'agendada', 'cerrada');

-- 2) Tabla
create table public.contact_requests (
  id               uuid primary key default gen_random_uuid(),
  kind             public.contact_kind not null,
  property_id      uuid references public.properties (id) on delete cascade,
  creative_id      uuid references public.creative_profiles (id) on delete cascade,
  post_id          uuid references public.creative_posts (id) on delete set null,
  recipient_id     uuid not null references auth.users (id) on delete cascade,
  requester_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  requester_name   text,
  requester_email  text,
  phone            text check (phone is null or length(phone) between 7 and 30),
  operation        text check (operation is null or operation in ('venta', 'renta')),
  preferred_times  text check (preferred_times is null or length(preferred_times) <= 200),
  message          text check (message is null or length(message) <= 1000),
  status           public.contact_status not null default 'nueva',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  -- una visita es de una propiedad; una cotización es para un creativo
  check (
    (kind = 'visita' and property_id is not null and creative_id is null)
    or (kind = 'cotizacion' and creative_id is not null and property_id is null)
  )
);

comment on table public.contact_requests is 'Solicitudes de visita (al vendedor) y de cotización (al creativo). ZAI-33 básico.';

create index contact_requests_recipient_idx on public.contact_requests (recipient_id, status, created_at desc);
create index contact_requests_requester_idx on public.contact_requests (requester_id, created_at desc);

create trigger contact_requests_set_updated_at
before update on public.contact_requests
for each row execute function public.set_updated_at();

-- 3) Antes de guardar: la base de datos completa y valida la solicitud.
--    security definer para poder leer auth.users y las propiedades del vendedor.
create or replace function public.contact_requests_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipient uuid;
  v_status    text;
begin
  new.requester_id := auth.uid();
  if new.requester_id is null then
    raise exception 'Inicia sesión para enviar una solicitud' using errcode = '42501';
  end if;

  if not exists (select 1 from auth.users where id = new.requester_id and email_confirmed_at is not null) then
    raise exception 'Confirma tu correo antes de enviar solicitudes' using errcode = 'P0001';
  end if;

  if new.kind = 'visita' then
    select p.seller_id, p.status::text into v_recipient, v_status
    from public.properties p where p.id = new.property_id;
    if v_recipient is null or v_status <> 'published' then
      raise exception 'Esta propiedad ya no está disponible' using errcode = 'P0001';
    end if;
    new.post_id := null;
  else
    select c.id into v_recipient from public.creative_profiles c where c.id = new.creative_id;
    if v_recipient is null then
      raise exception 'Este creativo ya no está disponible' using errcode = 'P0001';
    end if;
    -- la publicación solo se guarda si es de ese creativo
    if new.post_id is not null
       and not exists (select 1 from public.creative_posts cp where cp.id = new.post_id and cp.creative_id = new.creative_id) then
      new.post_id := null;
    end if;
    new.operation := null;
  end if;

  if v_recipient = new.requester_id then
    raise exception 'No puedes enviarte una solicitud a ti mismo' using errcode = 'P0001';
  end if;
  new.recipient_id := v_recipient;

  if (select count(*) from public.contact_requests r
      where r.requester_id = new.requester_id and r.created_at > now() - interval '24 hours') >= 5 then
    raise exception 'Llegaste al límite de 5 solicitudes por día. Intenta de nuevo mañana' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.contact_requests r
             where r.requester_id = new.requester_id and r.status <> 'cerrada'
               and (r.property_id = new.property_id or r.creative_id = new.creative_id)) then
    raise exception 'Ya tienes una solicitud abierta aquí. Te contactarán pronto' using errcode = 'P0001';
  end if;

  -- datos del cliente desde su cuenta (no desde el formulario)
  select coalesce(pr.full_name, split_part(u.email, '@', 1)), u.email
    into new.requester_name, new.requester_email
  from auth.users u left join public.profiles pr on pr.id = u.id
  where u.id = new.requester_id;

  new.status := 'nueva';
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

create trigger contact_requests_before_insert
before insert on public.contact_requests
for each row execute function public.contact_requests_before_insert();

-- 4) Solo el estado se puede cambiar después de enviarla
revoke update on public.contact_requests from anon, authenticated;
grant update (status) on public.contact_requests to authenticated;
revoke all on public.contact_requests from anon;

-- 5) Políticas
alter table public.contact_requests enable row level security;

create policy "El cliente envía solicitudes a su nombre"
on public.contact_requests for insert to authenticated
with check (requester_id = (select auth.uid()));

create policy "El cliente y quien la recibe ven la solicitud"
on public.contact_requests for select to authenticated
using (requester_id = (select auth.uid()) or recipient_id = (select auth.uid()));

create policy "Quien la recibe cambia el estado"
on public.contact_requests for update to authenticated
using (recipient_id = (select auth.uid()))
with check (recipient_id = (select auth.uid()));

create policy "Admin ve todas las solicitudes"
on public.contact_requests for select to authenticated
using ((select public.my_role()) = 'admin');
