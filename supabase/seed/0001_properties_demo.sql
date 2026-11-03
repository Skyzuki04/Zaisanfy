-- Datos demo: 3 propiedades
insert into public.properties (seller_id, status, title, description, operation, property_type, price, currency,
                               bedrooms, bathrooms, area_m2, state, city, neighborhood)
select u.id, v.status::public.property_status, v.title, v.description, v.operation, v.property_type, v.price, 'MXN',
       v.bedrooms, v.bathrooms, v.area_m2, v.state, v.city, v.neighborhood
from (select id from auth.users order by created_at limit 1) as u,
(values
  ('published', 'Casa con jardín en Zapopan', 'Casa de dos plantas con jardín y cochera para dos autos.',
   'venta', 'casa', 3850000, 3, 2.5, 210, 'Jalisco', 'Zapopan', 'Valle Real'),
  ('published', 'Departamento cerca del centro de Monterrey', 'Departamento amueblado con vista a la ciudad.',
   'renta', 'departamento', 18500, 2, 2, 95, 'Nuevo León', 'Monterrey', 'Obispado'),
  ('draft', 'Terreno para desarrollo en Querétaro', null,
   'venta', 'terreno', 2100000, 0, 0, 600, 'Querétaro', 'Querétaro', null)
) as v(status, title, description, operation, property_type, price, bedrooms, bathrooms, area_m2, state, city, neighborhood)
where not exists (
  select 1 from public.properties p where p.seller_id = u.id and p.title = v.title
);

-- Revisión: deben salir 3 filas
select id, status, title as titulo, price as precio, city as ciudad
from public.properties
order by created_at;
