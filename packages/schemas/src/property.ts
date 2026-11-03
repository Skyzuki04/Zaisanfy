import { z } from "zod";

export const PropertyStatus = z.enum(["draft", "published", "closed", "hidden"]);
export type PropertyStatus = z.infer<typeof PropertyStatus>;

export const PropertyType = z.enum(["casa", "departamento", "terreno", "local", "oficina"]);
export type PropertyType = z.infer<typeof PropertyType>;

export const Operation = z.enum(["venta", "renta"]);
export type Operation = z.infer<typeof Operation>;

export const Currency = z.enum(["MXN", "USD"]);

export const LocationSchema = z.object({
  state: z.string().min(2, "El estado es obligatorio"),
  city: z.string().min(2, "La ciudad es obligatoria"),
  neighborhood: z.string().min(2).optional(),
  address: z.string().optional(),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
});

export const MediaSchema = z.object({
  coverUrl: z.string().url().nullable().default(null),
  gallery: z.array(z.string().url()).max(30, "Máximo 30 fotos").default([]),
  panorama360Url: z.string().url().nullable().default(null),
});

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

export const PropertySchema = z.object({
  id: z.string().uuid(),
  seller_id: z.string().uuid(),
  status: PropertyStatus,
  data: PropertyDataSchema,
  created_at: z.string(),
  updated_at: z.string(),
});
export type Property = z.infer<typeof PropertySchema>;

export const NewPropertySchema = z.object({
  status: PropertyStatus.default("draft"),
  data: PropertyDataSchema,
});
export type NewProperty = z.infer<typeof NewPropertySchema>;
