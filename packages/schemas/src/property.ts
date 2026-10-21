import { z } from "zod";

/**
 * ZAI-19 · DATA-01 · Modelo de datos de propiedades
 *
 * Patrón del SRS: "columna vertebral relacional + cuerpo flexible JSONB".
 * - Las columnas fijas (id, seller_id, status, fechas) viven en SQL.
 * - El detalle de la propiedad vive en la columna `data` (JSONB) y su forma
 *   se define aquí. Este archivo es la única fuente de la verdad: lo usan el
 *   Escaparate, la Consola de socios y, más adelante, las Edge Functions.
 */

// Estados de una propiedad (RF-VEN-01). Deben coincidir con el enum de SQL.
export const PropertyStatus = z.enum(["draft", "published", "closed", "hidden"]);
export type PropertyStatus = z.infer<typeof PropertyStatus>;

export const PropertyType = z.enum(["casa", "departamento", "terreno", "local", "oficina"]);
export type PropertyType = z.infer<typeof PropertyType>;

export const Operation = z.enum(["venta", "renta"]);
export type Operation = z.infer<typeof Operation>;

export const Currency = z.enum(["MXN", "USD"]);

/** Ubicación: se usa en el filtro del buscador (RF-VIS-01) y más adelante en mapas. */
export const LocationSchema = z.object({
  state: z.string().min(2, "El estado es obligatorio"),
  city: z.string().min(2, "La ciudad es obligatoria"),
  neighborhood: z.string().min(2).optional(),
  address: z.string().optional(),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
});

/** Fotos y 360 guardados en Cloudinary (RF-VEN-02). Solo se guardan las URLs. */
export const MediaSchema = z.object({
  coverUrl: z.string().url().nullable().default(null),
  gallery: z.array(z.string().url()).max(30, "Máximo 30 fotos").default([]),
  panorama360Url: z.string().url().nullable().default(null),
});

/** Forma de la columna `data` (JSONB). */
export const PropertyDataSchema = z.object({
  title: z.string().min(3, "El título debe tener al menos 3 letras").max(120),
  description: z.string().max(2000).optional(),
  operation: Operation,
  propertyType: PropertyType,
  price: z.number().positive("El precio debe ser mayor a 0"),
  currency: Currency.default("MXN"),
  bedrooms: z.number().int().min(0).default(0),
  bathrooms: z.number().min(0).default(0),
  areaM2: z.number().positive().optional(),
  location: LocationSchema,
  media: MediaSchema.default({}),
});
export type PropertyData = z.infer<typeof PropertyDataSchema>;

/** Fila completa de la tabla `properties`, tal como la devuelve Supabase. */
export const PropertySchema = z.object({
  id: z.string().uuid(),
  seller_id: z.string().uuid(),
  status: PropertyStatus,
  data: PropertyDataSchema,
  created_at: z.string(),
  updated_at: z.string(),
});
export type Property = z.infer<typeof PropertySchema>;

/** Lo que manda el formulario al crear una propiedad (el resto lo pone la base de datos). */
export const NewPropertySchema = z.object({
  status: PropertyStatus.default("draft"),
  data: PropertyDataSchema,
});
export type NewProperty = z.infer<typeof NewPropertySchema>;
