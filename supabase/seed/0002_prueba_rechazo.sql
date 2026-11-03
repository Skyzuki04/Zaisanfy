-- Prueba: debe rechazar una propiedad sin precio
insert into public.properties (seller_id, title, operation, property_type, state, city)
select id, 'Propiedad sin precio', 'venta', 'casa', 'Puebla', 'Puebla'
from auth.users order by created_at limit 1;
