-- Prueba del "impersonate" del admin (RF-ADM-01). Resultado: IMPERSONATE OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000e221', 'admin.22@zaisanfy.test',    now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000e222', 'vendedor.22@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000e223', 'admin2.22@zaisanfy.test',   now(), '{"role": "visitante"}');
update public.profiles set role = 'admin' where id in ('00000000-0000-0000-0000-00000000e221', '00000000-0000-0000-0000-00000000e223');

set local role authenticated;

-- Un no-admin no puede, ni ve la bitácora, ni escribe en ella
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e222", "role": "authenticated"}', true);
do $$ begin
  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-00000000e223'); raise exception 'FALLA: un vendedor entró como otro';
  exception when insufficient_privilege then null; end;
  begin insert into public.impersonations (admin_id, target_id) values (auth.uid(), auth.uid()); raise exception 'FALLA: se escribió la bitácora directo';
  exception when insufficient_privilege then null; end;
end $$;

-- El admin
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e221", "role": "authenticated"}', true);
do $$
declare r record;
begin
  select * into r from public.admin_start_impersonation('00000000-0000-0000-0000-00000000e222', 'Soporte');
  if r.email <> 'vendedor.22@zaisanfy.test' or r.role <> 'vendedor' then raise exception 'FALLA: no regresó el correo y rol correctos'; end if;
  if (select count(*) from public.impersonations where target_id = '00000000-0000-0000-0000-00000000e222' and reason = 'Soporte') <> 1 then
    raise exception 'FALLA: no quedó en la bitácora';
  end if;

  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-00000000e221'); raise exception 'FALLA: entró como sí mismo';
  exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;
  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-00000000e223'); raise exception 'FALLA: entró como otro admin';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_start_impersonation('00000000-0000-0000-0000-0000000fffff'); raise exception 'FALLA: usuario inexistente';
  exception when no_data_found then null; end;
end $$;

reset role;
rollback;

select 'IMPERSONATE OK' as resultado;
