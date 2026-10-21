-- =====================================================================
-- ZAI-19 · Datos de prueba: 3 propiedades
-- Antes de correrlo: Supabase > Authentication > Users > Add user
-- (crea un usuario de prueba, por ejemplo vendedor.demo@zaisanfy.test).
-- Las propiedades se asignan al primer usuario que exista.
-- Se puede correr varias veces: si una propiedad de prueba ya existe, no se vuelve a crear.
-- =====================================================================

insert into public.properties (seller_id, status, data)
select u.id, v.status::public.property_status, v.data::jsonb
from (select id from auth.users order by created_at limit 1) as u,
(values
  ('published', '{
    "title": "Casa con jardín en Zapopan",
    "description": "Casa de dos plantas con jardín y cochera para dos autos.",
    "operation": "venta",
    "propertyType": "casa",
    "price": 3850000,
    "currency": "MXN",
    "bedrooms": 3,
    "bathrooms": 2.5,
    "areaM2": 210,
    "location": { "state": "Jalisco", "city": "Zapopan", "neighborhood": "Valle Real" },
    "media": { "coverUrl": null, "gallery": [], "panorama360Url": null }
  }'),
  ('published', '{
    "title": "Departamento cerca del centro de Monterrey",
    "description": "Departamento amueblado con vista a la ciudad.",
    "operation": "renta",
    "propertyType": "departamento",
    "price": 18500,
    "currency": "MXN",
    "bedrooms": 2,
    "bathrooms": 2,
    "areaM2": 95,
    "location": { "state": "Nuevo León", "city": "Monterrey", "neighborhood": "Obispado" },
    "media": { "coverUrl": null, "gallery": [], "panorama360Url": null }
  }'),
  ('draft', '{
    "title": "Terreno para desarrollo en Querétaro",
    "operation": "venta",
    "propertyType": "terreno",
    "price": 2100000,
    "currency": "MXN",
    "bedrooms": 0,
    "bathrooms": 0,
    "areaM2": 600,
    "location": { "state": "Querétaro", "city": "Querétaro" },
    "media": { "coverUrl": null, "gallery": [], "panorama360Url": null }
  }')
) as v(status, data)
where not exists (
  select 1 from public.properties p
  where p.seller_id = u.id
    and p.data->>'title' = v.data::jsonb->>'title'
);

-- Revisión: deben salir 3 filas
select id, status, data->>'title' as titulo, (data->>'price')::numeric as precio, data #>> '{location,city}' as ciudad
from public.properties
order by created_at;
