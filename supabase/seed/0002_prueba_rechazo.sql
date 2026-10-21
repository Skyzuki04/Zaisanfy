-- =====================================================================
-- ZAI-19 · Prueba de validación: este insert DEBE FALLAR
-- (no tiene precio). Si Supabase muestra un error con
-- "properties_data_has_price", la validación funciona.
-- =====================================================================
insert into public.properties (seller_id, data)
select id, '{"title": "Propiedad sin precio", "propertyType": "casa", "location": {"city": "Puebla"}}'::jsonb
from auth.users order by created_at limit 1;
