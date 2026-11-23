-- Prueba de reportes (ZAI-33, antitrolls). Resultado: REPORTES OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000c181', 'cliente.18@zaisanfy.test',  now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000c182', 'vendedor.18@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000c183', 'creativo.18@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000c184', 'admin.18@zaisanfy.test',    now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000c185', 'sinconfirmar.18@zaisanfy.test', null, '{"role": "visitante"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000c184';

insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000c183', 'Estudio 18');
insert into public.creative_posts (id, creative_id, title, category) values
  ('00000000-0000-0000-0000-0000000018b1', '00000000-0000-0000-0000-00000000c183', 'Render dudoso', 'render');
insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000018f1', '00000000-0000-0000-0000-00000000c182', 'published', 'Casa fraude', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

-- El cliente reporta la casa y la publicación
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c181", "role": "authenticated"}', true);
do $$ begin
  insert into public.reports (property_id, reason, details) values ('00000000-0000-0000-0000-0000000018f1', 'fraude', 'Pide anticipo por fuera');
  insert into public.reports (post_id, reason) values ('00000000-0000-0000-0000-0000000018b1', 'contenido_inapropiado');
  begin
    insert into public.reports (property_id, reason) values ('00000000-0000-0000-0000-0000000018f1', 'spam');
    raise exception 'FALLA: reportó dos veces lo mismo';
  exception when unique_violation then null;
  end;
  if (select count(*) from public.reports) <> 2 then raise exception 'FALLA: el cliente no ve sus reportes'; end if;
  begin
    perform public.resolve_report('propiedad', '00000000-0000-0000-0000-0000000018f1', 'ocultar');
    raise exception 'FALLA: un cliente ocultó una propiedad';
  exception when insufficient_privilege then null;
  end;
  if exists (select 1 from public.admin_reports()) then raise exception 'FALLA: un cliente ve la bandeja del admin'; end if;
end $$;

-- Sin correo confirmado no puede reportar; el dueño no se reporta a sí mismo
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c185", "role": "authenticated"}', true);
do $$ begin
  insert into public.reports (property_id, reason) values ('00000000-0000-0000-0000-0000000018f1', 'spam');
  raise exception 'FALLA: reportó sin confirmar su correo';
exception when sqlstate 'P0001' then null;
end $$;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c182", "role": "authenticated"}', true);
do $$ begin
  if exists (select 1 from public.reports) then raise exception 'FALLA: el vendedor ve quién lo reportó'; end if;
  insert into public.reports (property_id, reason) values ('00000000-0000-0000-0000-0000000018f1', 'spam');
  raise exception 'FALLA: se reportó a sí mismo';
exception when sqlstate 'P0001' then null;
end $$;

-- El admin ve la bandeja y oculta ambas
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c184", "role": "authenticated"}', true);
do $$ begin
  if (select count(*) from public.admin_reports()) <> 2 then raise exception 'FALLA: el admin no ve los 2 reportes'; end if;
  perform public.resolve_report('propiedad', '00000000-0000-0000-0000-0000000018f1', 'ocultar');
  perform public.resolve_report('publicacion', '00000000-0000-0000-0000-0000000018b1', 'ocultar');
  if exists (select 1 from public.admin_reports()) then raise exception 'FALLA: quedaron reportes abiertos'; end if;
end $$;

-- Ya no salen al público
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  if exists (select 1 from public.properties where id = '00000000-0000-0000-0000-0000000018f1') then raise exception 'FALLA: la casa oculta se ve'; end if;
  if exists (select 1 from public.creative_posts where id = '00000000-0000-0000-0000-0000000018b1') then raise exception 'FALLA: la publicación oculta se ve'; end if;
end $$;

-- El vendedor no la puede volver a publicar; el creativo sí ve la suya pero no la des-oculta
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c182", "role": "authenticated"}', true);
do $$ begin
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-0000000018f1';
  raise exception 'FALLA: el vendedor republicó una casa ocultada por reporte';
exception when sqlstate 'ZA005' then null;
end $$;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c183", "role": "authenticated"}', true);
do $$ begin
  update public.creative_posts set hidden = false, title = 'Render corregido' where id = '00000000-0000-0000-0000-0000000018b1';
  if not (select hidden from public.creative_posts where id = '00000000-0000-0000-0000-0000000018b1') then
    raise exception 'FALLA: el creativo des-ocultó su publicación';
  end if;
end $$;

reset role;
select 'REPORTES OK' as resultado;
rollback;
