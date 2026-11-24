-- RF-ADM-01 "impersonate": el admin entra a la cuenta de un usuario para ver exactamente lo que él ve.
-- La base decide quién puede (solo admin, nunca a sí mismo ni a otro admin) y deja bitácora.
-- El acceso (enlace de un solo uso) lo genera la Edge Function admin-impersonate con permisos de servidor.

create table public.impersonations (
  id bigint generated always as identity primary key,
  admin_id uuid not null references auth.users (id) on delete cascade,
  target_id uuid not null references auth.users (id) on delete cascade,
  reason text,
  created_at timestamptz not null default now()
);
comment on table public.impersonations is 'Bitácora: qué admin entró como qué usuario y cuándo (RF-ADM-01).';
create index impersonations_target_idx on public.impersonations (target_id, created_at desc);

alter table public.impersonations enable row level security;
-- Solo el admin la lee; nadie la escribe directo (solo admin_start_impersonation)
create policy impersonations_admin_select on public.impersonations for select to authenticated
  using (public.my_role() = 'admin');
revoke insert, update, delete on public.impersonations from anon, authenticated;

-- Revisa el permiso, registra en bitácora y regresa a quién y a qué app hay que entrar
create or replace function public.admin_start_impersonation(p_user uuid, p_reason text default null)
returns table (email text, role public.user_role)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_role public.user_role;
begin
  if public.my_role() is distinct from 'admin' then
    raise exception 'Solo el admin puede entrar como otro usuario' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'Ya estás en tu propia cuenta' using errcode = 'P0001';
  end if;
  select u.email, p.role into v_email, v_role
  from auth.users u join public.profiles p on p.id = u.id
  where u.id = p_user;
  if v_email is null then
    raise exception 'Ese usuario no existe' using errcode = 'P0002';
  end if;
  if v_role = 'admin' then
    raise exception 'No se puede entrar como otro admin' using errcode = '42501';
  end if;
  insert into public.impersonations (admin_id, target_id, reason) values (auth.uid(), p_user, nullif(trim(p_reason), ''));
  return query select v_email, v_role;
end;
$$;

revoke execute on function public.admin_start_impersonation(uuid, text) from public, anon;
grant execute on function public.admin_start_impersonation(uuid, text) to authenticated;
