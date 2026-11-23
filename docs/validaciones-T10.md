# Validaciones T10 en Zaisanfy

Todas viven en código, no en Mendix. Cada regla se revisa **dos veces**: en el formulario (Zod, `packages/schemas`) y en la base (constraint, trigger o RLS de Supabase).
Si alguien se brinca el formulario, la base la rechaza igual. El error de la base se traduce a español con `friendlyError()` (`packages/schemas/src/errors.ts`).

| Tipo T10 | Regla | Formulario (Zod) | Base de datos | Mensaje que ve el usuario |
|---|---|---|---|---|
| **Required** | Título, estado y ciudad de la propiedad | `PropertyDataSchema` | `properties_title_len`, `properties_state_len`, `properties_city_len` | "El título debe tener al menos 3 letras", "La ciudad es obligatoria" |
| **Required** | Correo, contraseña y nombre al registrarse | `SignUpSchema` | Supabase Auth | "Escribe un correo válido", "La contraseña debe tener al menos 8 caracteres" |
| **Required** | Confirmar correo antes de pedir cotización o visita | — | trigger `contact_requests_before_insert` | "Confirma tu correo antes de enviar solicitudes" |
| **Range** | Precio > 0, recámaras y baños ≥ 0, m² > 0 | `PropertyDataSchema` | `properties_price`, `properties_bedrooms`… | "El precio debe ser mayor a 0", "Las recámaras no pueden ser negativas" |
| **Range** | Latitud −90 a 90, longitud −180 a 180 | `LocationSchema` | `properties_lat`, `properties_lng` | "La latitud va de -90 a 90" |
| **Range** | Máximo 30 fotos, máximo 10 imágenes por publicación | `MediaSchema` | `save_property`, `save_post` | "Máximo 30 fotos" |
| **Range** | Máximo 5 solicitudes por día (antispam) | — | trigger `contact_requests_before_insert` | "Llegaste al límite de 5 solicitudes por día" |
| **Range (WIP)** | Propiedades publicadas a la vez según el plan: Freemium 3, Pro 25 | — | trigger `properties_publish_limit` (0013) | "Llegaste al límite de tu plan: 3 propiedades publicadas a la vez. Despublica otra propiedad o mejora tu plan" |
| **Range** | Anuncio de 1 a 60 días, sin empezar en el pasado | `MisAnuncios` | `ad_quote()` (0016) | "Un anuncio dura máximo 60 días" |
| **Range** | Fotógrafo con 2 h a 60 días de anticipación | `Fotografos` | trigger `service_requests_before_insert` (0017) | "Pide el fotógrafo con al menos 2 horas de anticipación" |
| **Regex** | Correo | `z.string().email()` | Supabase Auth | "Escribe un correo válido" |
| **Regex** | Teléfono `^[+\d][\d\s()-]{6,29}$` | `ContactRequestInputSchema` | `contact_requests.phone` (largo 7–30) | "Escribe un teléfono válido (solo números, espacios o guiones)" |
| **Regex** | Ligas de fotos, avatar y sitio web `^https?://` | `z.string().url()` | `property_photos.url`, `creative_profiles.website` | "Algún dato no es válido" |
| **Unique** | Un correo = una cuenta | — | Supabase Auth | "Ese correo ya tiene una cuenta. Inicia sesión." |
| **Unique** | Una propiedad una sola vez en Mi Lista | — | `bookmarks_pkey` (23505) | El corazón solo se queda marcado, sin error (la app ignora el repetido) |
| **Unique** | Una solicitud abierta por propiedad o creativo | — | trigger `contact_requests_before_insert` | "Ya tienes una solicitud abierta aquí" |
| **Unique** | Una sola foto 360 por propiedad | — | `property_photos_one_panorama` (23505) | "Esta propiedad ya tiene su foto 360°…" |
| **Unique** | Un solo plan vivo por usuario | — | `subscriptions_one_live` (23505) | "Ya tienes un plan activo…" |
| **Unique** | Un lead no se cobra dos veces | — | `lead_unlocks_pkey` + `unlock_lead_with_credit()` | "Ese contacto ya estaba desbloqueado. No se te cobró de nuevo." |
| **Unique** | Un fotógrafo abierto por propiedad, y solo uno toma cada pedido | — | `service_requests_one_open`, `accept_service()` | "Ya tienes un fotógrafo pedido…", "Otro fotógrafo ya tomó este pedido" |

## Evidencias para el sprint (capturas)

1. **Camino feliz:** crear una propiedad válida → "Propiedad guardada como borrador".
2. **Required:** dejar el título vacío → mensaje bajo el campo.
3. **Range:** precio 0 o recámaras −1 → mensaje bajo el campo.
4. **Regex:** teléfono con letras en "Agendar visita" → mensaje.
5. **Unique:** registrarse con un correo que ya existe → "Ese correo ya tiene una cuenta. Inicia sesión."
6. **Límite WIP:** vendedor Freemium con 3 publicadas intenta publicar la 4.ª → aviso rojo.

Las pruebas automáticas de todas estas reglas están en `supabase/tests/0000_todas_las_pruebas.sql`.
