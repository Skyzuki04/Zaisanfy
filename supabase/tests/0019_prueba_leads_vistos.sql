-- Prueba de "visto" en los leads (ZAI-35). Resultado: LEADS VISTOS OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d191', 'cliente.19@zaisanfy.test',  now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d192', 'vendedor.19@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000d193', 'otro.19@zaisanfy.test',     now(), '{"role": "vendedor"}');
insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city) values
  ('00000000-0000-0000-0000-0000000019f1', '00000000-0000-0000-0000-00000000d192', 'published', 'Casa 19', 'venta', 'casa', 100, 'Jalisco', 'Zapopan');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d191", "role": "authenticated"}', true);
insert into public.contact_requests (id, property_id) values ('00000000-0000-0000-0000-0000000019c1', '00000000-0000-0000-0000-0000000019f1');

-- Otro vendedor no lo puede marcar
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d193", "role": "authenticated"}', true);
do $$ begin
  if public.mark_inbox_seen(array['00000000-0000-0000-0000-0000000019c1'::uuid]) <> 0 then raise exception 'FALLA: otro vendedor marcó el lead'; end if;
end $$;

-- El dueño lo ve como nuevo, lo abre y queda visto (una sola vez)
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d192", "role": "authenticated"}', true);
do $$ begin
  if (select seen_at from public.my_inbox()) is not null then raise exception 'FALLA: el lead nuevo ya sale visto'; end if;
  if public.mark_inbox_seen(array['00000000-0000-0000-0000-0000000019c1'::uuid]) <> 1 then raise exception 'FALLA: no se marcó'; end if;
  if public.mark_inbox_seen(array['00000000-0000-0000-0000-0000000019c1'::uuid]) <> 0 then raise exception 'FALLA: se marcó dos veces'; end if;
  if (select seen_at from public.my_inbox()) is null then raise exception 'FALLA: no sale como visto'; end if;
  begin
    update public.contact_requests set seen_at = null where id = '00000000-0000-0000-0000-0000000019c1';
    raise exception 'FALLA: se cambió seen_at a mano';
  exception when insufficient_privilege then null;
  end;
end $$;

-- El cliente sabe que ya lo vieron
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d191", "role": "authenticated"}', true);
do $$ begin
  if (select seen_at from public.contact_requests where id = '00000000-0000-0000-0000-0000000019c1') is null then
    raise exception 'FALLA: el cliente no ve que ya lo vieron';
  end if;
end $$;

reset role;
select 'LEADS VISTOS OK' as resultado;
rollback;
