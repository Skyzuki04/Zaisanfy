-- Prueba del límite WIP por plan. Resultado: LIMITE WIP OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d301', 'freemium.13@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000d302', 'pro.13@zaisanfy.test',      now(), '{"role": "vendedor"}');

insert into public.subscriptions (user_id, plan_id, status, current_period_start, current_period_end) values
  ('00000000-0000-0000-0000-00000000d302', 'pro', 'activa', now() - interval '1 day', now() + interval '29 days');

-- 4 borradores de cada vendedor
insert into public.properties (id, seller_id, status, title, operation, property_type, price, state, city)
select ('00000000-0000-0000-0000-0000000013' || u || n)::uuid,
       ('00000000-0000-0000-0000-00000000d30' || u)::uuid,
       'draft', 'Casa ' || n, 'venta', 'casa', 100, 'Jalisco', 'Zapopan'
from generate_series(1, 2) u, generate_series(1, 4) n;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d301", "role": "authenticated"}', true);

do $$
declare q record;
begin
  -- Freemium publica 3 sin problema
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001311';
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001312';
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001313';

  -- La cuarta se bloquea con el código ZA001
  begin
    update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001314';
    raise exception 'FALLA: Freemium publicó una cuarta propiedad';
  exception when sqlstate 'ZA001' then null;
  end;

  -- Editar una que ya está publicada sí se puede
  update public.properties set title = 'Casa 1 editada' where id = '00000000-0000-0000-0000-000000001311';

  -- Si oculta una, ya puede publicar la cuarta
  update public.properties set status = 'hidden' where id = '00000000-0000-0000-0000-000000001311';
  update public.properties set status = 'published' where id = '00000000-0000-0000-0000-000000001314';

  select * into q from public.my_publish_quota();
  if q.plan_id <> 'freemium' or q.max_published <> 3 or q.published <> 3 then
    raise exception 'FALLA: my_publish_quota dice % % %', q.plan_id, q.max_published, q.published;
  end if;
end $$;

-- Pro publica las 4
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d302", "role": "authenticated"}', true);
do $$
begin
  update public.properties set status = 'published' where seller_id = '00000000-0000-0000-0000-00000000d302';
  if (select count(*) from public.properties where seller_id = '00000000-0000-0000-0000-00000000d302' and status = 'published') <> 4 then
    raise exception 'FALLA: Pro no pudo publicar 4';
  end if;
  if (select published from public.my_publish_quota()) <> 4 then
    raise exception 'FALLA: my_publish_quota no cuenta las de Pro';
  end if;
end $$;

-- Nadie de fuera puede preguntar el plan de otro
do $$
begin
  perform public.plan_of('00000000-0000-0000-0000-00000000d302');
  raise exception 'FALLA: plan_of se puede llamar desde la app';
exception when insufficient_privilege then null;
end $$;

select 'LIMITE WIP OK' as resultado;
rollback;
