-- Prueba del panel del Super Admin (RF-ADM-01 a 03). Resultado: SUPER ADMIN OK
begin;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000d211', 'admin.21@zaisanfy.test',    now(), '{"role": "visitante"}'),
  ('00000000-0000-0000-0000-00000000d212', 'vendedor.21@zaisanfy.test', now(), '{"role": "vendedor"}'),
  ('00000000-0000-0000-0000-00000000d213', 'creativo.21@zaisanfy.test', now(), '{"role": "creativo"}'),
  ('00000000-0000-0000-0000-00000000d214', 'cliente.21@zaisanfy.test',  now(), '{"role": "visitante"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000d211';

insert into public.properties (id, seller_id, status, title, description, operation, property_type, price, state, city, lat, lng, area_m2, neighborhood) values
  ('00000000-0000-0000-0000-0000000021f1', '00000000-0000-0000-0000-00000000d212', 'published', 'Casa completa con jardín en Zapopan centro',
   repeat('Descripción larga. ', 20), 'venta', 'casa', 100, 'Jalisco', 'Zapopan', 20.7, -103.4, 120, 'Centro'),
  ('00000000-0000-0000-0000-0000000021f2', '00000000-0000-0000-0000-00000000d212', 'published', 'Casa', null, 'venta', 'casa', 100, 'Jalisco', 'Zapopan', null, null, null, null);
insert into public.creative_profiles (id, display_name) values ('00000000-0000-0000-0000-00000000d213', 'Estudio 21');
insert into public.creative_posts (id, creative_id, title, category) values
  ('00000000-0000-0000-0000-0000000021b1', '00000000-0000-0000-0000-00000000d213', 'Render 21', 'render');

-- Métricas antes de los pagos de prueba: en producción ya hay suscripciones reales,
-- así que se compara la diferencia y no el total.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d211", "role": "authenticated"}', true);
select set_config('prueba.mrr_antes', mrr::text, true), set_config('prueba.churn_antes', churned::text, true)
from public.admin_metrics(3) limit 1;
reset role;

-- Pagos para las métricas: una Pro viva y un cambio de plan (no es churn)
insert into public.subscriptions (user_id, plan_id, status, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000d212', 'pro', 'activa', now() - interval '40 days', now()),
  ('00000000-0000-0000-0000-00000000d213', 'pro', 'cancelada', now() - interval '40 days', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-00000000d213', 'enterprise', 'activa', now() - interval '1 hour', now());

-- Un cliente no ve nada del admin
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d214", "role": "authenticated"}', true);
do $$ begin
  begin perform public.admin_users(); raise exception 'FALLA: un cliente ve los usuarios';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_set_suspended('00000000-0000-0000-0000-00000000d212', true); raise exception 'FALLA: un cliente suspendió';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_metrics(); raise exception 'FALLA: un cliente ve las métricas';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_seo_scores(); raise exception 'FALLA: un cliente ve el SEO Score';
  exception when insufficient_privilege then null; end;
  if exists (select 1 from public.suspensions) then raise exception 'FALLA: un cliente ve las suspensiones'; end if;
end $$;

-- El admin: usuarios, detalle, SEO, métricas y suspensión
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d211", "role": "authenticated"}', true);
do $$
declare
  d jsonb;
  m record;
begin
  if (select count(*) from public.admin_users('21@zaisanfy')) <> 4 then raise exception 'FALLA: el admin no ve los usuarios'; end if;
  if (select plan from public.admin_users('vendedor.21')) <> 'pro' then raise exception 'FALLA: no sale el plan del usuario'; end if;

  d := public.admin_user_detail('00000000-0000-0000-0000-00000000d212');
  if jsonb_array_length(d->'properties') <> 2 then raise exception 'FALLA: ver como no muestra sus propiedades'; end if;

  if (select score from public.admin_seo_scores() where id = '00000000-0000-0000-0000-0000000021f1') < 50
     or (select score from public.admin_seo_scores() where id = '00000000-0000-0000-0000-0000000021f2') > 30 then
    raise exception 'FALLA: el SEO Score no distingue la propiedad completa de la vacía';
  end if;
  if not exists (select 1 from public.admin_seo_scores() where id = '00000000-0000-0000-0000-0000000021f2' and 'Ubicación en el mapa (GEO)' = any (tips)) then
    raise exception 'FALLA: el SEO Score no sugiere la ubicación';
  end if;

  select * into m from public.admin_metrics(3) limit 1;
  if m.mrr - current_setting('prueba.mrr_antes')::numeric < 499 + 1499 then raise exception 'FALLA: el MRR no suma las suscripciones vivas (%)', m.mrr; end if;
  if m.churned <> current_setting('prueba.churn_antes')::bigint then raise exception 'FALLA: un cambio de plan contó como churn'; end if;

  begin perform public.admin_set_suspended('00000000-0000-0000-0000-00000000d211', true); raise exception 'FALLA: el admin se suspendió solo';
  exception when others then if sqlerrm like 'FALLA%' then raise; end if; end;

  perform public.admin_set_suspended('00000000-0000-0000-0000-00000000d212', true, 'Fraude');
  perform public.admin_set_role('00000000-0000-0000-0000-00000000d214', 'creativo');
  if (select role from public.profiles where id = '00000000-0000-0000-0000-00000000d214') <> 'creativo' then raise exception 'FALLA: no cambió el rol'; end if;
  if not exists (select 1 from public.properties where seller_id = '00000000-0000-0000-0000-00000000d212') then
    raise exception 'FALLA: el admin dejó de ver lo del suspendido';
  end if;
end $$;

-- El público ya no ve lo del suspendido
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  if exists (select 1 from public.properties where seller_id = '00000000-0000-0000-0000-00000000d212') then
    raise exception 'FALLA: se siguen viendo las propiedades del suspendido';
  end if;
end $$;

-- El suspendido no puede escribir nada
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d212", "role": "authenticated"}', true);
do $$ begin
  if not public.am_suspended() then raise exception 'FALLA: el suspendido no sabe que lo está'; end if;
  begin
    update public.properties set title = 'Me desuspendo' where id = '00000000-0000-0000-0000-0000000021f1';
    if found then raise exception 'FALLA: el suspendido editó su propiedad'; end if;
  exception when sqlstate 'ZA007' then null;
  end;
  begin
    insert into public.bookmarks (property_id) values ('00000000-0000-0000-0000-0000000021f1');
    raise exception 'FALLA: el suspendido guardó en Mi Lista';
  exception when sqlstate 'ZA007' then null;
  end;
end $$;

-- Reactivar
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d211", "role": "authenticated"}', true);
select public.admin_set_suspended('00000000-0000-0000-0000-00000000d212', false);
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
do $$ begin
  if (select count(*) from public.properties where seller_id = '00000000-0000-0000-0000-00000000d212') <> 2 then
    raise exception 'FALLA: al reactivar no regresaron sus propiedades';
  end if;
end $$;

reset role;
rollback;

select 'SUPER ADMIN OK' as resultado;
