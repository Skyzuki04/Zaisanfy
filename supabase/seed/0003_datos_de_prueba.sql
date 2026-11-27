-- Datos de prueba para la demo del sprint (25 nov 2026) · Dev: Damián
-- Llena el Escaparate y la Consola con datos de cada clase del Domain Model:
-- 6 cuentas, 8 propiedades (6 publicadas) con fotos y 360, 3 creativos con portafolio,
-- Mi Lista, solicitudes de visita y cotización, y un pedido de fotógrafo 360.
--
-- Reglas:
-- · Todo usa IDs fijos 00000000-0000-4000-8000-0000000dXXXX y correos @zaisanfy.test.
-- · Las cuentas demo NO tienen contraseña: no se puede iniciar sesión con ellas.
-- · Se puede correr varias veces: lo que ya existe no se duplica.
-- · Las fotos son las que el equipo ya subió a Cloudinary (no se sube nada nuevo).
-- · Para borrarlo todo: 0004_borrar_datos_de_prueba.sql
-- Se corre en Supabase → SQL Editor. Al final muestra un resumen.

begin;

-- 1) Cuentas (el trigger on_auth_user_created crea su perfil con el rol)
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
values
  ('00000000-0000-4000-8000-0000000d0001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo.vendedor.norte@zaisanfy.test',     now(), '{"role": "vendedor", "full_name": "Inmobiliaria Demo Norte"}', '{"provider": "email", "providers": ["email"]}', now(), now()),
  ('00000000-0000-4000-8000-0000000d0002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo.vendedor.occidente@zaisanfy.test', now(), '{"role": "vendedor", "full_name": "Inmobiliaria Demo Occidente"}', '{"provider": "email", "providers": ["email"]}', now(), now()),
  ('00000000-0000-4000-8000-0000000d0003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo.render@zaisanfy.test',             now(), '{"role": "creativo", "full_name": "Estudio Demo Render"}', '{"provider": "email", "providers": ["email"]}', now(), now()),
  ('00000000-0000-4000-8000-0000000d0004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo.arquitectura@zaisanfy.test',       now(), '{"role": "creativo", "full_name": "Arquitectura Demo Monterrey"}', '{"provider": "email", "providers": ["email"]}', now(), now()),
  ('00000000-0000-4000-8000-0000000d0005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo.foto360@zaisanfy.test',            now(), '{"role": "creativo", "full_name": "Foto 360 Demo Zapopan"}', '{"provider": "email", "providers": ["email"]}', now(), now()),
  ('00000000-0000-4000-8000-0000000d0006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo.cliente@zaisanfy.test',            now(), '{"role": "visitante", "full_name": "Cliente Demo"}', '{"provider": "email", "providers": ["email"]}', now(), now())
on conflict (id) do nothing;

-- 2) Perfiles públicos de los creativos (el de foto 360 con base de trabajo y radio)
insert into public.creative_profiles (id, display_name, specialty, bio, city, state, base_lat, base_lng, service_radius_km) values
  ('00000000-0000-4000-8000-0000000d0003', 'Estudio Demo Render', 'render3d', 'Renders de interiores y exteriores para preventa. Datos de prueba.', 'Guadalajara', 'Jalisco', null, null, 25),
  ('00000000-0000-4000-8000-0000000d0004', 'Arquitectura Demo Monterrey', 'arquitectura', 'Planos y proyectos de remodelación. Datos de prueba.', 'Monterrey', 'Nuevo León', null, null, 25),
  ('00000000-0000-4000-8000-0000000d0005', 'Foto 360 Demo Zapopan', 'fotografia', 'Fotografía 360 a domicilio en la zona metropolitana. Datos de prueba.', 'Zapopan', 'Jalisco', 20.7214, -103.3918, 30)
on conflict (id) do nothing;

-- 3) Propiedades: 3 publicadas + 1 borrador por vendedor (el plan Freemium permite 3 publicadas)
insert into public.properties (id, seller_id, status, title, description, operation, property_type, price, currency,
                               bedrooms, bathrooms, area_m2, state, city, neighborhood, address, lat, lng) values
  ('00000000-0000-4000-8000-0000000d1001', '00000000-0000-4000-8000-0000000d0001', 'published', 'Departamento con terraza en San Pedro',
   'Departamento luminoso con terraza, dos cajones de estacionamiento y amenidades.', 'venta', 'departamento', 6200000, 'MXN',
   2, 2, 120, 'Nuevo León', 'San Pedro Garza García', 'Del Valle', 'Calzada del Valle 400', 25.6531, -100.3591),
  ('00000000-0000-4000-8000-0000000d1002', '00000000-0000-4000-8000-0000000d0001', 'published', 'Casa familiar en Cumbres',
   'Casa de dos plantas en privada con vigilancia, cerca de escuelas y parques. Incluye recorrido 360.', 'venta', 'casa', 4350000, 'MXN',
   3, 2.5, 180, 'Nuevo León', 'Monterrey', 'Cumbres', 'Paseo de los Leones 2100', 25.7339, -100.4049),
  ('00000000-0000-4000-8000-0000000d1003', '00000000-0000-4000-8000-0000000d0001', 'published', 'Local comercial en el centro de Monterrey',
   'Local a pie de calle con mucho paso peatonal, ideal para cafetería o tienda.', 'renta', 'local', 38000, 'MXN',
   0, 1, 85, 'Nuevo León', 'Monterrey', 'Centro', 'Calle Morelos 850', 25.6714, -100.3094),
  ('00000000-0000-4000-8000-0000000d1004', '00000000-0000-4000-8000-0000000d0001', 'draft', 'Terreno campestre en Santiago',
   'Borrador: falta subir fotos.', 'venta', 'terreno', 1900000, 'MXN',
   0, 0, 800, 'Nuevo León', 'Santiago', 'El Cercado', null, 25.4253, -100.1511),
  ('00000000-0000-4000-8000-0000000d1005', '00000000-0000-4000-8000-0000000d0002', 'published', 'Casa con patio en Valle Real',
   'Casa amplia con patio, cocina integral y estudio. Incluye recorrido 360.', 'venta', 'casa', 7800000, 'MXN',
   4, 3.5, 320, 'Jalisco', 'Zapopan', 'Valle Real', 'Av. Valle Real 1500', 20.7329, -103.4405),
  ('00000000-0000-4000-8000-0000000d1006', '00000000-0000-4000-8000-0000000d0002', 'published', 'Departamento amueblado en la Americana',
   'Departamento amueblado a una cuadra de Chapultepec, listo para habitar.', 'renta', 'departamento', 21500, 'MXN',
   2, 2, 90, 'Jalisco', 'Guadalajara', 'Americana', 'Calle Libertad 1800', 20.6736, -103.3700),
  ('00000000-0000-4000-8000-0000000d1007', '00000000-0000-4000-8000-0000000d0002', 'published', 'Oficina en Puerta de Hierro',
   'Oficina acondicionada con sala de juntas y vista a la ciudad.', 'renta', 'oficina', 45000, 'MXN',
   0, 2, 140, 'Jalisco', 'Zapopan', 'Puerta de Hierro', 'Av. Patria 2085', 20.7099, -103.4128),
  ('00000000-0000-4000-8000-0000000d1008', '00000000-0000-4000-8000-0000000d0002', 'draft', 'Casa en Tlaquepaque',
   'Borrador: falta confirmar el precio.', 'venta', 'casa', 2650000, 'MXN',
   3, 2, 150, 'Jalisco', 'San Pedro Tlaquepaque', 'Centro', null, 20.6409, -103.2933)
on conflict (id) do nothing;

-- 4) Fotos (posición 0 = portada) y fotos 360. Son imágenes que el equipo ya tiene en Cloudinary.
insert into public.property_photos (property_id, kind, url, position)
select v.property_id::uuid, v.kind::public.photo_kind, v.url, v.position
from (values
  ('00000000-0000-4000-8000-0000000d1001', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977727/wyaywqxsjhq7jifgdxef.avif', 0),
  ('00000000-0000-4000-8000-0000000d1001', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977730/ptihrztixxcge917ispu.avif', 1),
  ('00000000-0000-4000-8000-0000000d1002', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977728/g8hipncpek1dwoban5y7.avif', 0),
  ('00000000-0000-4000-8000-0000000d1002', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978405/bd7ejwvzz1eql0v6wndt.avif', 1),
  ('00000000-0000-4000-8000-0000000d1002', 'panorama', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977765/thg5yoe1j0ynec29vwod.webp', 0),
  ('00000000-0000-4000-8000-0000000d1003', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978407/aenhicdfhnynzvxp4in0.avif', 0),
  ('00000000-0000-4000-8000-0000000d1005', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977730/ptihrztixxcge917ispu.avif', 0),
  ('00000000-0000-4000-8000-0000000d1005', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978405/bd7ejwvzz1eql0v6wndt.avif', 1),
  ('00000000-0000-4000-8000-0000000d1005', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978407/aenhicdfhnynzvxp4in0.avif', 2),
  ('00000000-0000-4000-8000-0000000d1005', 'panorama', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977765/thg5yoe1j0ynec29vwod.webp', 0),
  ('00000000-0000-4000-8000-0000000d1006', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977727/wyaywqxsjhq7jifgdxef.avif', 0),
  ('00000000-0000-4000-8000-0000000d1006', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977728/g8hipncpek1dwoban5y7.avif', 1),
  ('00000000-0000-4000-8000-0000000d1007', 'foto', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978405/bd7ejwvzz1eql0v6wndt.avif', 0)
) as v(property_id, kind, url, position)
where not exists (select 1 from public.property_photos f
                  where f.property_id = v.property_id::uuid and f.kind = v.kind::public.photo_kind and f.position = v.position);

-- 5) Portafolio de los creativos (relacionado por ciudad y tipo de propiedad para la sección Inspiración)
insert into public.creative_posts (id, creative_id, title, description, category, property_type, city) values
  ('00000000-0000-4000-8000-0000000d2001', '00000000-0000-4000-8000-0000000d0003', 'Sala contemporánea para departamento', 'Render de sala con tonos cálidos.', 'render', 'departamento', 'Guadalajara'),
  ('00000000-0000-4000-8000-0000000d2002', '00000000-0000-4000-8000-0000000d0003', 'Cocina integral con comedor', 'Propuesta de cocina abierta para casa familiar.', 'render', 'casa', 'Zapopan'),
  ('00000000-0000-4000-8000-0000000d2003', '00000000-0000-4000-8000-0000000d0003', 'Paleta de materiales cálidos', 'Idea de acabados para remodelar.', 'idea', null, 'Guadalajara'),
  ('00000000-0000-4000-8000-0000000d2004', '00000000-0000-4000-8000-0000000d0004', 'Planta de casa de 3 recámaras', 'Distribución con cochera para dos autos.', 'plano', 'casa', 'Monterrey'),
  ('00000000-0000-4000-8000-0000000d2005', '00000000-0000-4000-8000-0000000d0004', 'Estudio en casa compacto', 'Idea para aprovechar una recámara pequeña como oficina.', 'idea', 'departamento', 'San Pedro Garza García'),
  ('00000000-0000-4000-8000-0000000d2006', '00000000-0000-4000-8000-0000000d0005', 'Recorrido 360 de una recámara', 'Ejemplo de fotografía 360 tomada en Zapopan.', 'idea', 'casa', 'Zapopan')
on conflict (id) do nothing;

insert into public.post_images (post_id, url, position)
select v.post_id::uuid, v.url, v.position
from (values
  ('00000000-0000-4000-8000-0000000d2001', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978307/uok9gpvpoyyjhcq9mleb.avif', 0),
  ('00000000-0000-4000-8000-0000000d2001', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978407/aenhicdfhnynzvxp4in0.avif', 1),
  ('00000000-0000-4000-8000-0000000d2002', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978405/bd7ejwvzz1eql0v6wndt.avif', 0),
  ('00000000-0000-4000-8000-0000000d2003', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978559/b07jcndopsnxjdag9ig3.avif', 0),
  ('00000000-0000-4000-8000-0000000d2004', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978499/wimyw0qusrxmmol4wjth.avif', 0),
  ('00000000-0000-4000-8000-0000000d2005', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792978306/yowfig2uopsuzdr6szt3.avif', 0),
  ('00000000-0000-4000-8000-0000000d2006', 'https://res.cloudinary.com/qpf3rowy/image/upload/v1792977765/thg5yoe1j0ynec29vwod.webp', 0)
) as v(post_id, url, position)
where not exists (select 1 from public.post_images i where i.post_id = v.post_id::uuid and i.position = v.position);

-- 6) Mi Lista del cliente demo
insert into public.bookmarks (user_id, property_id) values
  ('00000000-0000-4000-8000-0000000d0006', '00000000-0000-4000-8000-0000000d1002'),
  ('00000000-0000-4000-8000-0000000d0006', '00000000-0000-4000-8000-0000000d1005'),
  ('00000000-0000-4000-8000-0000000d0006', '00000000-0000-4000-8000-0000000d1006')
on conflict do nothing;

-- 7) Solicitudes del cliente demo. Las reglas de la base piden que las mande el propio cliente,
--    así que se insertan "a su nombre" (request.jwt.claims) solo dentro de esta transacción.
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-0000000d0006", "role": "authenticated"}', true);

insert into public.contact_requests (id, property_id, phone, operation, preferred_times, message)
select '00000000-0000-4000-8000-0000000d3001', '00000000-0000-4000-8000-0000000d1005', '3312345678', 'venta', 'Sábados por la mañana',
       'Me interesa la casa. ¿Puedo agendar una visita? (dato de prueba)'
where not exists (select 1 from public.contact_requests where id = '00000000-0000-4000-8000-0000000d3001');

insert into public.contact_requests (id, property_id, phone, operation, preferred_times, message)
select '00000000-0000-4000-8000-0000000d3002', '00000000-0000-4000-8000-0000000d1002', '8112345678', 'venta', 'Entre semana después de las 6',
       'Quisiera ver la casa en persona. (dato de prueba)'
where not exists (select 1 from public.contact_requests where id = '00000000-0000-4000-8000-0000000d3002');

insert into public.contact_requests (id, post_id, phone, message)
select '00000000-0000-4000-8000-0000000d3003', '00000000-0000-4000-8000-0000000d2002', '3312345678',
       'Quiero una cotización para una cocina parecida. (dato de prueba)'
where not exists (select 1 from public.contact_requests where id = '00000000-0000-4000-8000-0000000d3003');

insert into public.contact_requests (id, creative_id, phone, message)
select '00000000-0000-4000-8000-0000000d3004', '00000000-0000-4000-8000-0000000d0004', '8112345678',
       'Necesito planos para remodelar mi casa. (dato de prueba)'
where not exists (select 1 from public.contact_requests where id = '00000000-0000-4000-8000-0000000d3004');

-- 8) Pedido de fotógrafo 360 del vendedor de occidente (lo ve el fotógrafo demo de Zapopan)
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-0000000d0002", "role": "authenticated"}', true);

insert into public.service_requests (id, property_id, scheduled_at, notes, address, lat, lng)
select '00000000-0000-4000-8000-0000000d4001', '00000000-0000-4000-8000-0000000d1007', now() + interval '3 days',
       'Tocar en recepción. (dato de prueba)', '', null, null
where not exists (select 1 from public.service_requests where id = '00000000-0000-4000-8000-0000000d4001');

select set_config('request.jwt.claims', '', true);

commit;

-- Resumen: cuántos datos de prueba hay de cada tipo
select 'cuentas' as dato, count(*) as total from auth.users where email like 'demo.%@zaisanfy.test'
union all select 'creativos', count(*) from public.creative_profiles where id::text like '00000000-0000-4000-8000-0000000d%'
union all select 'propiedades publicadas', count(*) from public.properties where id::text like '00000000-0000-4000-8000-0000000d1%' and status = 'published'
union all select 'propiedades en borrador', count(*) from public.properties where id::text like '00000000-0000-4000-8000-0000000d1%' and status = 'draft'
union all select 'fotos y 360', count(*) from public.property_photos where property_id::text like '00000000-0000-4000-8000-0000000d1%'
union all select 'publicaciones', count(*) from public.creative_posts where id::text like '00000000-0000-4000-8000-0000000d2%'
union all select 'imágenes de publicaciones', count(*) from public.post_images where post_id::text like '00000000-0000-4000-8000-0000000d2%'
union all select 'Mi Lista', count(*) from public.bookmarks where user_id = '00000000-0000-4000-8000-0000000d0006'
union all select 'solicitudes', count(*) from public.contact_requests where id::text like '00000000-0000-4000-8000-0000000d3%'
union all select 'pedidos de fotógrafo', count(*) from public.service_requests where id::text like '00000000-0000-4000-8000-0000000d4%';
