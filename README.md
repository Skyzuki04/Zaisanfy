# Zaisanfy

Plataforma PropTech para buscar propiedades con recorridos 360 y una red de creativos (arquitectos y artistas 3D).
Proyecto de **Metodologías Ágiles · Universidad Tecmilenio**.

**Equipo:** Eduardo Rivera Crespo · Ireri Guerrero Domínguez · Owen Iván Rojas Mendoza (Developer)

**Tablero Kanban:** Mendix Epics · proyecto "Zaisanfy" · alcance: Fase 1 (MVP) y Fase 2 (Growth).

---

## Estructura del repositorio

Un solo repositorio (monorepo) con las 3 apps de la "Tríada Desacoplada" del SRS:

| Carpeta | App | Tecnología | Fase |
|---|---|---|---|
| `apps/visitor` | Escaparate público (`www.zaisanfy.com`) | Next.js (SSR/ISR) | F1 y F2 |
| `apps/partner` | Consola de socios (`app.zaisanfy.com`) | Vite + React | F1 y F2 |
| `apps/admin` | Núcleo administrativo (`admin-core.zaisanfy.com`) | Refine (pendiente) | Fuera de F1/F2 |
| `packages/schemas` | Esquemas Zod compartidos (modelo de datos) | TypeScript + Zod | F1 (DATA-01) |

Servicios: **Supabase** (base de datos, Auth y RLS) · **Cloudinary** (fotos y 360).

## Qué hace cada app

- **Escaparate** (`apps/visitor`): lo ve cualquiera, sin cuenta. Buscador, detalle con recorrido 360, muro de inspiración y perfiles de creativos.
  Con cuenta: Mi Lista, contactar al vendedor o agendar visita, pedir cotización a un creativo y Mis solicitudes.
  Aquí está el **registro único** (cliente, vendedor o creativo).
- **Consola de socios** (`apps/partner`): vendedores publican y administran propiedades (fotos, 360, estados); creativos editan su perfil y portafolio.
  Los dos atienden sus **Solicitudes**.
- Las dos apps usan la misma cuenta de Supabase y se pasan la sesión al cruzar de una a otra (ver [docs/flujos.md](docs/flujos.md)).

## Cómo correrlo

Requisitos: Node.js 20 o superior y Git.

```bash
npm install                 # instala las dependencias de todas las apps
cp .env.example apps/visitor/.env.local
cp .env.example apps/partner/.env
npm run dev:visitor         # Escaparate en http://localhost:3000
npm run dev:partner         # Consola de socios en http://localhost:5173
npm run build               # compila todas las apps (sirve para revisar antes de un PR)
```

### Variables de entorno

Están todas en [`.env.example`](.env.example). Las mínimas para correr en local:

| App | Archivo | Variables |
|---|---|---|
| Escaparate | `apps/visitor/.env.local` | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME`, `NEXT_PUBLIC_PARTNER_URL` |
| Consola | `apps/partner/.env` | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_CLOUDINARY_CLOUD_NAME`, `VITE_CLOUDINARY_UPLOAD_PRESET`, `VITE_VISITOR_URL` |

La URL y la llave **anon** salen de Supabase → Project Settings → API. La llave `service_role` nunca va en el navegador.

## Base de datos (Supabase)

Las migraciones viven en [`supabase/migrations`](supabase/migrations) y se corren **en orden** en Supabase → SQL Editor → New query → pegar → Run.
Cada una tiene su prueba en [`supabase/tests`](supabase/tests): se corre igual, termina con un mensaje `… OK` y no deja datos (hace ROLLBACK).

| # | Migración | Qué crea | Prueba |
|---|---|---|---|
| 0001 | `0001_properties.sql` | ZAI-19 · tabla `properties` | — |
| 0002 | `0002_profiles_y_permisos.sql` | ZAI-20 · `profiles`, roles y RLS de propiedades | `0002_prueba_permisos.sql` → `ZAI-20 OK` |
| 0003 | `0003_creative_profiles.sql` | ZAI-27 · perfil público del creativo | `0003_prueba_perfiles.sql` → `ZAI-27 OK` |
| 0004 | `0004_creative_posts.sql` | ZAI-28 · portafolio (renders, planos, ideas) | `0004_prueba_portafolio.sql` → `ZAI-28 OK` |
| 0005 | `0005_bookmarks.sql` | ZAI-31 · Mi Lista | `0005_prueba_mi_lista.sql` → `ZAI-31 OK` |
| 0006 | `0006_contact_requests.sql` | ZAI-33 básico · solicitudes de visita y cotización | `0006_prueba_solicitudes.sql` → `ZAI-33 OK` |
| 0007 | `0007_upgrade_role.sql` | Mejora de cuenta: cliente → vendedor o creativo | `0007_prueba_mejora_de_cuenta.sql` → `MEJORA DE CUENTA OK` |

Para revisar qué hay en la base sin cambiar nada: [`supabase/inventario.sql`](supabase/inventario.sql) (marca cada objeto como OK, FALTA o SOBRA).

Una migración nueva se agrega con el siguiente número (`0008_…`), nunca editando una que ya se corrió.

## Por dónde empezar si eres de backend

1. [docs/flujos.md](docs/flujos.md): mapa por rol (visitante, cliente, vendedor, creativo, admin) con cada pantalla, botón, a dónde lleva
   y qué tabla o política de Supabase usa. Al final está la lista de **pendientes de F3** (correo de aviso, captcha, pagos y premium, verificación, moderación).
2. [docs/permisos.md](docs/permisos.md): roles, quién puede hacer qué, qué pide cuenta y qué pide verificación, y los candados contra abuso.
3. [docs/modelo-de-datos.md](docs/modelo-de-datos.md): estructura de `properties` y los esquemas Zod de `packages/schemas`.
4. Las reglas viven en la base de datos (RLS y triggers), no solo en la app. Si algo se valida, se valida en SQL y se prueba en `supabase/tests`.

## Reglas del equipo

### Ramas
- `main` siempre debe funcionar. **Nadie sube cambios directo a `main`.**
- Cada tarjeta del tablero tiene su rama: `feature/ZAI-<número>-<descripcion-corta>`
  - Ejemplo: `feature/ZAI-19-modelo-de-datos`

### Commits
- Empiezan con el ID de la tarjeta y dicen qué se hizo, en presente:
  - `ZAI-19: crear tabla properties en Supabase`
  - `ZAI-21: agregar formulario de alta de propiedades`

### Pull Requests
1. Al terminar una tarjeta, se abre un Pull Request de la rama hacia `main`.
2. El PR menciona la tarjeta (`ZAI-xx`) y cómo probarla.
3. El equipo revisa la tarjeta contra sus criterios de aceptación.
4. Se hace merge y la tarjeta pasa a **Done** en el tablero.

### Definition of Done
Una tarjeta está terminada cuando:
- cumple sus criterios de aceptación,
- otra persona del equipo la revisó,
- su código está en `main` sin errores.

### Variables de entorno
- Las llaves van en `.env` (nunca en el código y nunca en GitHub).
- Si se agrega una variable nueva, también se agrega a `.env.example` sin el valor real.
