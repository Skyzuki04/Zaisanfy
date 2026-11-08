# Modelo de datos

La base está en **3FN** (todas las tablas): cada columna guarda un solo dato, depende solo de la llave de su tabla y no se copia nada que se pueda sacar de otra tabla.
Esto reemplaza el patrón "columna relacional + cuerpo JSONB" del SRS: desde la migración `0008` el detalle de la propiedad vive en columnas normales y las fotos en su propia tabla.

Las apps siguen trabajando con la forma de `PropertyData` de Zod (`packages/schemas`): `toProperty()` arma ese objeto a partir de las columnas y `save_property()` lo guarda.

## Diagrama entidad-relación

```mermaid
erDiagram
    AUTH_USERS ||--|| PROFILES : "tiene"
    PROFILES ||--o| CREATIVE_PROFILES : "si es creativo"
    AUTH_USERS ||--o{ PROPERTIES : "vende"
    PROPERTIES ||--o{ PROPERTY_PHOTOS : "fotos y 360"
    CREATIVE_PROFILES ||--o{ CREATIVE_POSTS : "publica"
    CREATIVE_POSTS ||--|{ POST_IMAGES : "imágenes"
    AUTH_USERS ||--o{ BOOKMARKS : "guarda"
    PROPERTIES ||--o{ BOOKMARKS : "guardada en"
    AUTH_USERS ||--o{ CONTACT_REQUESTS : "pide"
    PROPERTIES ||--o{ CONTACT_REQUESTS : "visita"
    CREATIVE_PROFILES ||--o{ CONTACT_REQUESTS : "cotización"
    CREATIVE_POSTS ||--o{ CONTACT_REQUESTS : "cotización sobre trabajo"
    PLANS ||--o{ SUBSCRIPTIONS : "plan"
    AUTH_USERS ||--o| BILLING_CUSTOMERS : "cliente Stripe"
    AUTH_USERS ||--o{ SUBSCRIPTIONS : "suscribe"
    AUTH_USERS ||--o{ PAYMENTS : "paga"
    SUBSCRIPTIONS ||--o{ SUBSCRIPTION_PAYMENTS : "cobros"
    PAYMENTS ||--o| SUBSCRIPTION_PAYMENTS : ""
    AUTH_USERS ||--o{ CREDIT_MOVEMENTS : "créditos"
    CONTACT_REQUESTS ||--o| LEAD_UNLOCKS : "desbloqueo"
    PAYMENTS ||--o| LEAD_UNLOCKS : "pagado con"
    CREDIT_MOVEMENTS ||--o| LEAD_UNLOCKS : "o con créditos"
    PROPERTIES ||--o{ ADS : "anuncio"
    PAYMENTS ||--o| ADS : "pagado con"
    ADS ||--o{ AD_EVENTS : "vistas y clics"

    PROFILES { uuid id PK "FK auth.users" enum role text full_name }
    PROPERTIES {
        uuid id PK
        uuid seller_id FK
        enum status
        text title
        text description
        text operation
        text property_type
        numeric price
        text currency
        int bedrooms
        numeric bathrooms
        numeric area_m2
        text state
        text city
        text neighborhood
        text address
        float lat
        float lng
    }
    PROPERTY_PHOTOS { uuid id PK uuid property_id FK enum kind text url smallint position }
    CREATIVE_PROFILES { uuid id PK "FK profiles" text display_name text specialty text bio text city text state text avatar_url text website }
    CREATIVE_POSTS { uuid id PK uuid creative_id FK text title text description enum category text property_type text city }
    POST_IMAGES { uuid id PK uuid post_id FK text url smallint position }
    BOOKMARKS { uuid user_id PK "FK" uuid property_id PK "FK" }
    CONTACT_REQUESTS { uuid id PK uuid requester_id FK uuid property_id FK uuid creative_id FK uuid post_id FK text phone text operation text preferred_times text message enum status }
    PLANS { text id PK text name numeric price_mxn text stripe_price_id int max_published int monthly_credits bool can_advertise }
    BILLING_CUSTOMERS { uuid user_id PK "FK" text stripe_customer_id }
    SUBSCRIPTIONS { uuid id PK uuid user_id FK text plan_id FK enum status text stripe_subscription_id timestamptz current_period_end bool cancel_at_period_end }
    PAYMENTS { uuid id PK uuid user_id FK numeric amount_mxn enum status text stripe_payment_intent_id }
    SUBSCRIPTION_PAYMENTS { uuid payment_id PK "FK" uuid subscription_id FK }
    CREDIT_MOVEMENTS { uuid id PK uuid user_id FK int amount enum reason }
    LEAD_UNLOCKS { uuid request_id PK "FK" uuid payment_id FK uuid credit_movement_id FK }
    ADS { uuid id PK uuid property_id FK enum placement date starts_on date ends_on uuid payment_id FK }
    AD_EVENTS { bigint id PK uuid ad_id FK enum kind }
```

Todas las tablas tienen `created_at`; las que se editan tienen además `updated_at`.

## Tablas

| Tabla | Qué guarda | Llave |
|---|---|---|
| `profiles` | Rol y nombre de cada cuenta | `id` = usuario |
| `properties` | Propiedades: datos, precio y ubicación en columnas | `id` |
| `property_photos` | Una fila por foto (`kind = foto`, la posición 0 es la portada) y la 360 (`kind = panorama`, una por propiedad) | `id`; único (`property_id`, `kind`, `position`) |
| `creative_profiles` | Perfil público del creativo | `id` = perfil |
| `creative_posts` | Publicaciones del portafolio | `id` |
| `post_images` | 1 a 10 imágenes por publicación, en orden | `id`; único (`post_id`, `position`) |
| `bookmarks` | Mi Lista: usuario ↔ propiedad | (`user_id`, `property_id`) |
| `contact_requests` | Solicitud de un cliente. Va a **una sola** cosa: `property_id` (visita), `creative_id` (cotización desde el perfil) o `post_id` (cotización sobre una publicación) | `id` |
| `plans` | Freemium, Pro, Enterprise: precio y límites (provisionales, los confirma el PO) | `id` |
| `billing_customers` | Cliente de Stripe de cada usuario | `user_id` |
| `subscriptions` | Suscripción de Stripe; solo una viva por usuario | `id` |
| `payments` | Cada cobro de Stripe | `id` |
| `subscription_payments` | Qué cobros son de qué suscripción | `payment_id` |
| `credit_movements` | Créditos que entran (+) o salen (−). El saldo es la suma | `id` |
| `lead_unlocks` | Solicitudes desbloqueadas, con un pago **o** con créditos, una sola vez | `request_id` |
| `ads` | Anuncios pagados de una propiedad en el buscador o el muro | `id` |
| `ad_events` | Cada vista o clic de un anuncio | `id` |

## Datos que se calculan (no se guardan)

Guardarlos rompería la 3FN, así que se calculan en la base:

| Dato | Cómo se obtiene |
|---|---|
| Tipo de solicitud (`visita` / `cotizacion`) | Función `kind(contact_requests)`. Las apps lo piden con `select("*, kind")` |
| Quién recibe una solicitud | `request_recipient()`: el vendedor de la propiedad, el creativo o el dueño de la publicación |
| Nombre y correo del cliente para quien recibe | `my_inbox()`: la bandeja de la Consola, con los datos actuales del cliente |
| Plan actual | `my_plan()`: la suscripción activa o `freemium` |
| Saldo de créditos | `my_credits()`: suma de `credit_movements` |
| Anuncio vigente | `ad_is_live()`: hoy (hora de México) dentro de las fechas pagadas, con el pago en `pagado` y la propiedad publicada |
| Vistas y clics de un anuncio | `my_ad_stats()`: los anuncios del vendedor con `count(*)` sobre `ad_events` |

## Validación en dos niveles

1. **Zod (apps):** revisa el formulario antes de guardar y muestra mensajes claros.
2. **Base de datos:** `check` en cada columna (título 3–120, precio > 0, tipo y operación válidos, estado y ciudad, URLs `https://`, de 1 a 10 imágenes, hasta 30 fotos). Nada entra roto aunque alguien se salte la app.

`save_property()` y `save_post()` guardan la fila y sus fotos o imágenes en una sola transacción: si algo falla, no se guarda nada.

## Formas normales

| Forma | Cómo se cumple |
|---|---|
| 1FN | No hay JSON ni listas: las fotos y las imágenes son filas en su propia tabla |
| 2FN | Las tablas con llave compuesta (`bookmarks`) no tienen columnas que dependan de una parte de la llave |
| 3FN | Nada se copia: el tipo, el destinatario y los datos del cliente de una solicitud, el plan actual y el saldo se calculan. Una cotización sobre una publicación guarda solo `post_id` (el creativo sale de la publicación) |
