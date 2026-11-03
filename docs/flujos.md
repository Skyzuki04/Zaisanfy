# Flujos y botones por rol

Mapa de pantallas de las dos apps: qué ve cada rol, a dónde lleva cada botón y qué tabla o política de Supabase usa.
Sirve para revisar que no haya callejones sin salida y como punto de partida para el equipo de backend.

- **Escaparate** (`apps/visitor`, Next.js, `http://localhost:3000`): público. Clientes (rol `visitante`).
- **Consola** (`apps/partner`, Vite, `http://localhost:5173`): vendedores y creativos.
- Reglas de permisos: [permisos.md](permisos.md). Modelo de datos: [modelo-de-datos.md](modelo-de-datos.md).

Regla general: **libre para mirar, cuenta para interactuar, cuenta verificada para publicar o pagar.**

## Cuentas: una sola para todo

- **Un solo registro**, en el Escaparate: `/entrar` → Crear cuenta. Se elige el tipo en 3 tarjetas:
  **Busco casa** (`visitante`, por defecto) · **Vendo o rento** (`vendedor`) · **Ofrezco servicios creativos** (`creativo`).
  El rol viaja en `options.data.role` y lo asigna el trigger `handle_new_user` (nadie se registra como admin).
- La Consola conserva su propio login y registro **solo para socios** (vendedor o creativo), con el aviso
  "¿Buscas casa? Crea tu cuenta de cliente en el Escaparate".
- Con la misma cuenta se entra a las dos apps.
- Después de entrar: si llegó con `next` (por ejemplo, desde "Contactar al vendedor"), regresa ahí; si no, el cliente va al inicio
  y el socio ve "Te llevamos a tu Consola" y cruza con su sesión.
- **Mejora de cuenta:** un cliente puede volverse vendedor o creativo desde su menú de cuenta
  ("Quiero vender o rentar" / "Ofrecer mis servicios creativos"). Usa el RPC `upgrade_role` (migración 0007):
  solo visitante → vendedor o creativo; nunca admin ni bajar de rol. Después cruza a la Consola.
- Sin sesión, el menú del Escaparate muestra **Únete como socio** (`/entrar?modo=registro&tipo=vendedor`) y **Entrar**.

## Sesión entre las dos apps

Son orígenes distintos y cada uno guarda su sesión. Para no quedar con cuentas cruzadas, los enlaces entre apps
pasan la sesión en el hash (`#zs_at=…&zs_rt=…`). El hash no llega a ningún servidor y se borra de la barra al leerse.

| De | Enlace | Código |
|---|---|---|
| Escaparate → Consola | Botón del menú según rol, botones del dueño en su perfil | `visitor/src/components/ConsoleLink.tsx` |
| Consola → Escaparate | "Ver Escaparate", "Ver perfil público", "Ver publicada" | `withSession()` en `partner/src/components/Layout.tsx` |
| Recibe la Consola | `adoptHandoff()` | `partner/src/auth/AuthProvider.tsx` |
| Recibe el Escaparate | `start()` | `visitor/src/lib/bookmarks.ts` |

Si el token llega inválido: la Consola cierra sesión y manda a `/entrar`; el Escaparate cierra la sesión local.

- El traspaso **solo ocurre al dar clic** en un botón de cruce; nunca en silencio.
- Si se cruza **sin sesión**, el enlace lleva `#zs_logout=1` y la otra app cierra la suya (`signOut({ scope: "local" })`), para no quedarse con una cuenta vieja.
- "Salir" usa `signOut()` global: revoca la sesión en el servidor, así que la otra app ya no puede renovarla.
- El Escaparate **siempre muestra quién tiene la sesión** (inicial y nombre en el menú, con panel de cuenta), y el formulario de contacto dice "Enviarás esta solicitud como … · ¿No eres tú? Cambiar de cuenta".

## 1. Visitante sin cuenta (Escaparate)

| Pantalla | Botones / enlaces | Lleva a | Supabase |
|---|---|---|---|
| Inicio `/` | Buscador (filtros) · Limpiar · tarjeta de propiedad · corazón | `/?…` · `/` · `/propiedad/[id]` · `/entrar?next=…` | `properties` select (política "Todos ven las propiedades publicadas") |
| Menú | Propiedades · Inspiración · Mi Lista · Entrar | `/` · `/muro` · `/mi-lista` · `/entrar` | — |
| Propiedad `/propiedad/[id]` | ← Volver · corazón · **Contactar al vendedor · Agendar visita** · Iniciar 360 · fotos · ideas de creativos | `/` · `/entrar?next=/propiedad/[id]` (ambos) · visor · galería · `/publicaciones/[id]` | `properties` (publicadas), `creative_posts` |
| Muro `/muro` | Filtros por categoría · paginación · tarjeta | `/muro?…` · `/publicaciones/[id]` | `creative_posts`, `creative_profiles` (públicos) |
| Publicación `/publicaciones/[id]` | ← Portafolio del creativo · **Solicitar cotización** | `/creativos/[id]` · `/entrar?next=…` | `creative_posts` |
| Perfil creativo `/creativos/[id]` | ← Volver al muro · **Solicitar cotización** · publicaciones | `/muro` · `/entrar?next=…` · `/publicaciones/[id]` | `creative_profiles` ("Todos ven los perfiles de creativos") |
| Mi Lista / Mis solicitudes sin sesión | Iniciar sesión o crear cuenta | `/entrar?next=…` | — |
| Entrar `/entrar` | Iniciar sesión · Crear cuenta (3 tipos) · ← Regresar | regresa a `next` o `/`; socio → Consola | Supabase Auth; trigger `handle_new_user` crea `profiles` con el rol elegido |
| Menú sin sesión | Únete como socio · Entrar | `/entrar?modo=registro&tipo=vendedor` · `/entrar` | — |
| No encontrado (propiedad, publicación, creativo) | Botón para seguir | `/` o `/muro` | — |

## 2. Visitante con cuenta (cliente)

Todo lo anterior, más:

| Pantalla | Botones / enlaces | Lleva a | Supabase |
|---|---|---|---|
| Menú | Mi Lista (n) · menú de cuenta (inicial y nombre): Mi Lista, Mis solicitudes, **Quiero vender o rentar**, **Ofrecer mis servicios creativos**, Salir | `/mi-lista` · `/mis-solicitudes` · Consola · cierra sesión | `upgrade_role` RPC (no ve botón de Consola mientras sea cliente) |
| Corazón (cualquier tarjeta o detalle) | Guardar / quitar | se queda | `bookmarks` insert/delete (solo publicadas, solo lo suyo) |
| Mi Lista `/mi-lista` | Tarjetas · quitar · "Quitar de la lista" si ya no está publicada · vacío: Buscar propiedades | `/propiedad/[id]` · `/` | `bookmarks` + `properties` |
| Propiedad → Contactar | Formulario (comprar/rentar, horario, teléfono, mensaje) → Enviar · Cancelar | confirmación con **Ver mis solicitudes** / **Seguir viendo propiedades** | `contact_requests` insert (trigger `contact_requests_before_insert`) |
| Creativo / publicación → Cotizar | Igual; desde una publicación se guarda solo `post_id` | confirmación con **Ver mis solicitudes** / **Seguir en el muro** | `contact_requests` insert |
| Mis solicitudes `/mis-solicitudes` | Cada solicitud con su estado · enlace a la propiedad o creativo · vacío: Ver propiedades / Ver creativos | `/propiedad/[id]` · `/creativos/[id]` · `/` · `/muro` | `contact_requests` select ("El cliente y quien la recibe ven la solicitud") |
| Si entra a la Consola | "Tu cuenta es de cliente" · **Ir al Escaparate** · Salir y entrar con otra cuenta | Escaparate · `/entrar` | — |

Errores que ve el cliente al contactar (los lanza la base de datos): correo sin confirmar, propiedad no publicada,
límite de 5 por día, ya tiene una solicitud abierta ahí, contactarse a sí mismo.

## 3. Vendedor

| Pantalla | Botones / enlaces | Lleva a | Supabase |
|---|---|---|---|
| Escaparate, menú | **Mis propiedades** (con sesión pasada) | Consola `/propiedades` | `profiles.role` |
| Consola, entrar `/entrar` | Iniciar sesión · Crear cuenta (Vendedor/Creativo) · enlace "Entra al Escaparate" para clientes | `/` → `/propiedades` | Supabase Auth, `profiles` |
| Menú Consola | Mis propiedades · Solicitudes · Ver Escaparate ↗ · nombre + rol · Salir | — | — |
| Mis propiedades `/propiedades` | + Nueva propiedad · Editar · Ver publicada ↗ · Publicar / Cerrar / Ocultar / Borrador · Borrar · vacío: + Crear mi primera propiedad | `/propiedades/nueva` · `/propiedades/[id]` · Escaparate · se queda con aviso | `properties` (solo las suyas) |
| Nueva / editar `/propiedades/nueva`, `/propiedades/[id]` | Datos · fotos y 360 (Cloudinary) · Guardar · Cancelar · ← Mis propiedades | `/propiedades` con aviso "guardada como borrador, dale Publicar" | `save_property()` (propiedad + `property_photos`); Cloudinary upload sin firma |
| Propiedad ajena o inexistente | Volver a mis propiedades | `/propiedades` | RLS ya lo impide |
| Solicitudes `/solicitudes` | Abiertas / Todas · WhatsApp · Responder por correo · cambiar estado · enlace a la propiedad · vacío: Ver mis propiedades | `wa.me`, `mailto:` · `/propiedades/[id]` | `my_inbox()` + `contact_requests` update(status) ("Quien la recibe cambia el estado") |

## 4. Creativo

| Pantalla | Botones / enlaces | Lleva a | Supabase |
|---|---|---|---|
| Escaparate, menú | **Mi perfil** (con sesión pasada) | Consola `/perfil` | `profiles.role` |
| Su perfil público `/creativos/[id]` | Recuadro "Este es tu perfil": + Subir trabajo · Editar perfil · Mi portafolio · portafolio vacío: + Subir mi primer trabajo | Consola `/portafolio/nueva`, `/perfil`, `/portafolio` | — (no se ve su propio botón de cotizar) |
| Menú Consola | Mi perfil · Mi portafolio · Solicitudes · Ver Escaparate ↗ | — | — |
| Mi perfil `/perfil` | Foto · datos · Guardar · Ver mi perfil público ↗ · + Subir trabajo · al guardar: "¿Qué sigue?" con Subir mi primer trabajo / Ir a mi portafolio / Ver perfil público | `/portafolio/nueva` · `/portafolio` · Escaparate | `creative_profiles` upsert |
| Mi portafolio `/portafolio` | + Nueva publicación · Ver en mi perfil ↗ · Editar · Borrar · sin perfil: Ir a Mi perfil · vacío: + Subir mi primer trabajo | `/portafolio/nueva` · `/portafolio/[id]` · `/perfil` | `creative_posts` |
| Nueva / editar publicación | Imágenes (Cloudinary) · Guardar · Cancelar · ajena: Volver a mi portafolio | `/portafolio` con aviso | `save_post()` (publicación + `post_images`) |
| Solicitudes `/solicitudes` | Igual que el vendedor, con cotizaciones · enlace a la publicación · vacío: + Subir más trabajos | — | `my_inbox()` |

## 5. Admin

Ve "Mi consola" en el Escaparate y en la Consola "Mis propiedades" (todas) y "Solicitudes" (las que le llegan).
Puede ver todas las solicitudes por la política "Admin ve todas las solicitudes"; no hay pantalla de moderación todavía.

## Pendiente para backend (F3)

| Tema | Qué falta | Notas |
|---|---|---|
| Correo de aviso de solicitudes | Avisar al vendedor/creativo cuando llega una solicitud y al cliente cuando cambia el estado | Supabase Database Webhook o Edge Function sobre `contact_requests` (insert / update de `status`) + proveedor de correo (Resend, etc.) |
| Captcha | Cloudflare Turnstile en el registro de las dos apps | Supabase Auth → Attack Protection; pasar `captchaToken` en `signUp` / `signInWithPassword` |
| Pagos y suscripciones (ZAI-32) | Página de planes con Stripe Checkout y webhook en una Edge Function | **La base ya está (0009).** El webhook, con la service key, escribe en `billing_customers`, `subscriptions`, `payments` y `subscription_payments`, y suma créditos del plan en `credit_movements` (`reason = plan`). Las apps leen `plans`, `my_plan()` y `my_credits()` |
| Pay-wall y desbloqueo de leads (ZAI-33/34) | Ocultar el contacto del cliente en cotizaciones hasta desbloquear | Tablas `lead_unlocks` y `credit_movements` listas. Falta: que `my_inbox()` devuelva correo y teléfono solo si hay fila en `lead_unlocks`, y la Edge Function que cobra (pago o créditos) e inserta el desbloqueo |
| Límites por plan | Aplicar `plans.max_published` al publicar | Un trigger en `properties` que compare con `my_plan()` |
| Anuncios (ZAI-36) | Compra del anuncio y espacio "Patrocinado" | Tablas `ads` y `ad_events` listas; el anuncio se ve solo si `ad_is_live()`. La app registra vistas y clics en `ad_events` |
| Verificación de vendedores | Teléfono por SMS y/o revisión manual antes de publicar | Bandera `verified` en `profiles`, solo la cambia admin o el servidor |
| WhatsApp del vendedor para el cliente | Mostrar el WhatsApp del vendedor al cliente después de enviar la solicitud | Hoy el vendedor contacta al cliente; falta un campo de contacto del vendedor y exponerlo solo al solicitante |
| Reportar y moderar | Botón "Reportar" y pantalla de admin para ocultar (`hidden`) | Tabla `reports` con límite por usuario |
| Notificaciones en la app | Contador de solicitudes nuevas en el menú de la Consola | Hoy se ve dentro de la pestaña Solicitudes |
| Confirm email | Debe estar encendido en producción | Sin correo confirmado la base de datos rechaza solicitudes |

## Migraciones (aplicar en orden en el SQL Editor)

`0001_properties` → `0002_profiles_y_permisos` → `0003_creative_profiles` → `0004_creative_posts` → `0005_bookmarks` → `0006_contact_requests` → `0007_upgrade_role` → `0008_tercera_forma_normal` → `0009_pagos`.
Cada una tiene su prueba en `supabase/tests/` que termina con `… OK` y no deja datos.
