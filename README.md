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

## Cómo correrlo

Requisitos: Node.js 20 o superior y Git.

```bash
npm install                 # instala las dependencias de todas las apps
cp .env.example apps/visitor/.env.local
cp .env.example apps/partner/.env
npm run dev:visitor         # Escaparate en http://localhost:3000
npm run dev:partner         # Consola de socios en http://localhost:5173
```

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
