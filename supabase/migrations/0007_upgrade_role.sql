-- Mejora de cuenta (visitante a vendedor o creativo)
create or replace function public.upgrade_role(new_role public.user_role)
returns public.user_role
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_role_value public.user_role;
begin
  if auth.uid() is null then
    raise exception 'Inicia sesión para cambiar tu tipo de cuenta' using errcode = '42501';
  end if;

  if new_role not in ('vendedor', 'creativo') then
    raise exception 'Solo puedes volverte vendedor o creativo' using errcode = 'P0001';
  end if;

  select p.role into current_role_value from public.profiles p where p.id = auth.uid() for update;
  if current_role_value is null then
    raise exception 'No encontramos tu perfil' using errcode = 'P0001';
  end if;

  if current_role_value = new_role then
    return current_role_value;
  end if;

  if current_role_value <> 'visitante' then
    raise exception 'Tu cuenta ya es de tipo %. Para cambiarla escribe a soporte', current_role_value using errcode = 'P0001';
  end if;

  update public.profiles set role = new_role where id = auth.uid();
  return new_role;
end;
$$;

comment on function public.upgrade_role(public.user_role) is 'Un visitante se vuelve vendedor o creativo. Nunca admin ni bajar de rol.';

revoke all on function public.upgrade_role(public.user_role) from public, anon;
grant execute on function public.upgrade_role(public.user_role) to authenticated;
