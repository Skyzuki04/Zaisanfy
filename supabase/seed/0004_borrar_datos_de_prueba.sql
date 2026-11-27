-- Borra TODOS los datos de prueba de 0003_datos_de_prueba.sql y nada más.
-- Solo toca las 6 cuentas demo (IDs 00000000-0000-4000-8000-0000000d000X, correos demo.*@zaisanfy.test).
-- Al borrar la cuenta, la base borra en cascada su perfil, sus propiedades y fotos, su portafolio,
-- su Mi Lista, sus solicitudes y sus pedidos de fotógrafo.
-- Se corre en Supabase → SQL Editor. Al final debe salir 0 en todo.

begin;

delete from auth.users
where id in ('00000000-0000-4000-8000-0000000d0001', '00000000-0000-4000-8000-0000000d0002',
             '00000000-0000-4000-8000-0000000d0003', '00000000-0000-4000-8000-0000000d0004',
             '00000000-0000-4000-8000-0000000d0005', '00000000-0000-4000-8000-0000000d0006')
  and email like 'demo.%@zaisanfy.test';

commit;

select 'cuentas demo' as dato, count(*) as quedan from auth.users where email like 'demo.%@zaisanfy.test'
union all select 'propiedades demo', count(*) from public.properties where id::text like '00000000-0000-4000-8000-0000000d1%'
union all select 'publicaciones demo', count(*) from public.creative_posts where id::text like '00000000-0000-4000-8000-0000000d2%'
union all select 'solicitudes demo', count(*) from public.contact_requests where id::text like '00000000-0000-4000-8000-0000000d3%'
union all select 'pedidos demo', count(*) from public.service_requests where id::text like '00000000-0000-4000-8000-0000000d4%';
