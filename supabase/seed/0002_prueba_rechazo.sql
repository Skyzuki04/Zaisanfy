-- Prueba: debe rechazar una propiedad sin precio
insert into public.properties (seller_id, data)
select id, '{"title": "Propiedad sin precio", "propertyType": "casa", "location": {"city": "Puebla"}}'::jsonb
from auth.users order by created_at limit 1;
