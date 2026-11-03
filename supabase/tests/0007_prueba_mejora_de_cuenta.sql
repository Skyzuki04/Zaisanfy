-- Prueba de mejora de cuenta
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000f001', 'cliente.f@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000f002', 'cliente.g@zaisanfy.test', '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000f003', 'vendedor.f@zaisanfy.test', '{"role": "vendedor"}');

-- Cliente F se vuelve vendedor
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f001", "role": "authenticated"}', true);

do $$ begin
  begin
    perform public.upgrade_role('admin');
    raise exception 'FALLA: un cliente se hizo admin';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;

  if public.upgrade_role('vendedor') <> 'vendedor' then raise exception 'FALLA: no se volvió vendedor'; end if;
  if (select role from public.profiles where id = auth.uid()) <> 'vendedor' then raise exception 'FALLA: el perfil no cambió'; end if;

  begin
    perform public.upgrade_role('creativo');
    raise exception 'FALLA: un vendedor cambió a creativo';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
  begin
    perform public.upgrade_role('visitante');
    raise exception 'FALLA: se pudo bajar a visitante';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;

  begin
    update public.profiles set role = 'admin' where id = auth.uid();
    raise exception 'FALLA: se editó el rol sin el RPC';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000f002", "role": "authenticated"}', true);

do $$ begin
  if public.upgrade_role('creativo') <> 'creativo' then raise exception 'FALLA: no se volvió creativo'; end if;
end $$;

reset role;
do $$ begin
  if (select role from public.profiles where id = '00000000-0000-0000-0000-00000000f003') <> 'vendedor' then raise exception 'FALLA: cambió el rol de otro usuario'; end if;
end $$;

-- Sin sesión no se puede
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  begin
    perform public.upgrade_role('vendedor');
    raise exception 'FALLA: sin sesión se pudo cambiar de rol';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;

select 'MEJORA DE CUENTA OK' as resultado;
