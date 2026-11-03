-- Prueba de solicitudes. Resultado: ZAI-33 OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000e001', 'cliente.a@zaisanfy.test', now(), '{"role": "visitante", "full_name": "Cliente A"}'),
  ('00000000-0000-0000-0000-00000000e002', 'cliente.b@zaisanfy.test', now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000e003', 'vendedor.e@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000e004', 'creativo.e@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000e005', 'sin.confirmar@zaisanfy.test', null, '{"role": "visitante"}');

insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000001f1', '00000000-0000-0000-0000-00000000e003', 'published',
   'Publicada de prueba', 'venta', 'casa', 100, 'Jalisco', 'Zapopan'),
  ('00000000-0000-0000-0000-0000000001f2', '00000000-0000-0000-0000-00000000e003', 'draft',
   'Borrador de prueba', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

insert into public.creative_profiles (id, display_name, specialty) values
  ('00000000-0000-0000-0000-00000000e004', 'Estudio de prueba', 'interiorismo');

-- Cliente A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e001", "role": "authenticated"}', true);

do $$
declare r public.contact_requests;
begin
  insert into public.contact_requests (property_id, requester_id, message)
  values ('00000000-0000-0000-0000-0000000001f1', '00000000-0000-0000-0000-00000000e002', 'Me interesa')
  returning * into r;
  if public.request_recipient(r.property_id, r.creative_id, r.post_id) <> '00000000-0000-0000-0000-00000000e003' then raise exception 'FALLA: el destinatario no es el vendedor'; end if;
  if r.requester_id <> '00000000-0000-0000-0000-00000000e001' then raise exception 'FALLA: se mandó a nombre de otro'; end if;
  if public.kind(r) <> 'visita' then raise exception 'FALLA: el tipo no es visita'; end if;
  if exists (select 1 from public.my_inbox()) then raise exception 'FALLA: el cliente ve la bandeja del vendedor'; end if;

  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: dos solicitudes abiertas para la misma propiedad';
  exception when raise_exception then
    if sqlerrm not like '%abierta%' then raise exception 'FALLA: una abierta por propiedad (%)', sqlerrm; end if;
  end;

  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f2');
    raise exception 'FALLA: se pidió visita a una propiedad no publicada';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;

  insert into public.contact_requests (creative_id, message) values ('00000000-0000-0000-0000-00000000e004', 'Cotización');
  if (select count(*) from public.contact_requests) <> 2 then raise exception 'FALLA: A no ve sus solicitudes'; end if;

  -- el cliente no puede cambiar el estado
  update public.contact_requests set status = 'cerrada';
  if exists (select 1 from public.contact_requests where status <> 'nueva') then raise exception 'FALLA: el cliente cambió el estado'; end if;
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);

do $$
declare i int;
begin
  if exists (select 1 from public.contact_requests) then raise exception 'FALLA: B ve solicitudes de A'; end if;
end $$;

do $$ begin
  for i in 1..5 loop
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e003", "role": "authenticated"}', true);
    update public.contact_requests set status = 'cerrada' where requester_id = '00000000-0000-0000-0000-00000000e002';
  end loop;
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);
end $$;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e002", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.contact_requests (creative_id) values ('00000000-0000-0000-0000-00000000e004');
    raise exception 'FALLA: no se aplicó el límite de 5 por día';
  exception when raise_exception then
    if sqlerrm not like '%límite%' then raise exception 'FALLA: límite de 5 por día (%)', sqlerrm; end if;
  end;
end $$;

-- El vendedor ve y atiende solo lo suyo
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e003", "role": "authenticated"}', true);

do $$
declare n int;
begin
  if exists (select 1 from public.contact_requests where property_id is null) then raise exception 'FALLA: el vendedor ve cotizaciones del creativo'; end if;
  if not exists (select 1 from public.my_inbox() where requester_name = 'Cliente A' and requester_email = 'cliente.a@zaisanfy.test' and property_title = 'Publicada de prueba') then
    raise exception 'FALLA: la bandeja no muestra los datos del cliente';
  end if;
  update public.contact_requests set status = 'contactado' where requester_id = '00000000-0000-0000-0000-00000000e001';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLA: el vendedor no pudo cambiar el estado'; end if;

  begin
    update public.contact_requests set message = 'cambiado' where requester_id = '00000000-0000-0000-0000-00000000e001';
    raise exception 'FALLA: el vendedor cambió el mensaje del cliente';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: el vendedor se contactó a sí mismo';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
end $$;

-- El creativo ve su cotización
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e004", "role": "authenticated"}', true);

do $$ begin
  if (select count(*) from public.contact_requests) <> 1 then raise exception 'FALLA: el creativo no ve solo su cotización'; end if;
  if (select count(*) from public.my_inbox() where kind = 'cotizacion') <> 1 then raise exception 'FALLA: la cotización no llega a la bandeja del creativo'; end if;
end $$;

-- Correo sin confirmar
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000e005", "role": "authenticated"}', true);

do $$ begin
  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: se aceptó una solicitud con el correo sin confirmar';
  exception when raise_exception then
    if sqlerrm like 'FALLA%' then raise; end if;
  end;
end $$;

-- Sin sesión no hay nada
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);

do $$ begin
  begin
    if exists (select 1 from public.contact_requests) then raise exception 'FALLA: sin sesión se ven solicitudes'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.contact_requests (property_id) values ('00000000-0000-0000-0000-0000000001f1');
    raise exception 'FALLA: sin sesión se pudo enviar una solicitud';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
rollback;

select 'ZAI-33 OK' as resultado;
