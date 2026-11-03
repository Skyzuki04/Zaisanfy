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

export type PhotoRow = { url: string; kind: "foto" | "panorama"; position: number };

export type PropertyRow = {
  id: string;
  seller_id: string;
  status: PropertyStatus;
  title: string;
  description: string | null;
  operation: Operation;
  property_type: PropertyType;
  price: number;
  currency: "MXN" | "USD";
  bedrooms: number;
  bathrooms: number;
  area_m2: number | null;
  state: string;
  city: string;
  neighborhood: string | null;
  address: string | null;
  lat: number | null;
  lng: number | null;
  photos?: PhotoRow[] | null;
  created_at: string;
  updated_at: string;
};

export const PROPERTY_SELECT = "*, photos:property_photos(url, kind, position)";

const opt = <T>(v: T | null | undefined) => (v === null || v === undefined ? undefined : v);

export function toProperty(row: PropertyRow): Property {
  const photos = [...(row.photos ?? [])].sort((a, b) => a.position - b.position);
  const gallery = photos.filter((p) => p.kind === "foto").map((p) => p.url);
  return {
    id: row.id,
    seller_id: row.seller_id,
    status: row.status,
    created_at: row.created_at,
    updated_at: row.updated_at,
    data: {
      title: row.title,
      description: opt(row.description),
      operation: row.operation,
      propertyType: row.property_type,
      price: Number(row.price),
      currency: row.currency,
      bedrooms: row.bedrooms,
      bathrooms: Number(row.bathrooms),
      areaM2: row.area_m2 === null ? undefined : Number(row.area_m2),
      location: {
        state: row.state,
        city: row.city,
        neighborhood: opt(row.neighborhood),
        address: opt(row.address),
        lat: opt(row.lat),
        lng: opt(row.lng),
      },
      media: {
        coverUrl: gallery[0] ?? null,
        gallery,
        panorama360Url: photos.find((p) => p.kind === "panorama")?.url ?? null,
      },
    },
  };
}

export function toSavePropertyArgs(id: string | null, d: PropertyData) {
  const { coverUrl, gallery } = d.media;
  const photos = coverUrl ? [coverUrl, ...gallery.filter((u) => u !== coverUrl)] : gallery;
  return {
    p_id: id,
    p_title: d.title,
    p_description: d.description ?? null,
    p_operation: d.operation,
    p_property_type: d.propertyType,
    p_price: d.price,
    p_currency: d.currency,
    p_bedrooms: d.bedrooms,
    p_bathrooms: d.bathrooms,
    p_area_m2: d.areaM2 ?? null,
    p_state: d.location.state,
    p_city: d.location.city,
    p_neighborhood: d.location.neighborhood ?? null,
    p_address: d.location.address ?? null,
    p_lat: d.location.lat ?? null,
    p_lng: d.location.lng ?? null,
    p_photos: photos.slice(0, 30),
    p_panorama: d.media.panorama360Url,
  };
}
