import { z } from "zod";
import { PropertyType } from "./property";

/**
 * ZAI-27 · RF-CRE-01 · Perfil público del creativo (tabla creative_profiles).
 * Los valores deben coincidir con los CHECK de supabase/migrations/0003_creative_profiles.sql.
 */
export const Specialty = z.enum(["arquitectura", "render3d", "interiorismo", "fotografia", "otro"]);
export type Specialty = z.infer<typeof Specialty>;

export const SPECIALTY_LABEL: Record<Specialty, string> = {
  arquitectura: "Arquitectura",
  render3d: "Render 3D",
  interiorismo: "Interiorismo",
  fotografia: "Fotografía 360",
  otro: "Otro",
};

const optionalUrl = z.string().url("Escribe una URL completa (https://…)").nullable().default(null);

/** Lo que manda el formulario "Mi perfil". */
export const CreativeProfileInputSchema = z.object({
  display_name: z.string().trim().min(2, "Escribe tu nombre o el de tu estudio").max(80),
  specialty: Specialty.default("otro"),
  bio: z.string().max(1000, "Máximo 1000 caracteres").nullable().default(null),
  city: z.string().trim().min(2).max(80).nullable().default(null),
  state: z.string().trim().min(2).max(80).nullable().default(null),
  avatar_url: optionalUrl,
  website: optionalUrl,
});
export type CreativeProfileInput = z.infer<typeof CreativeProfileInputSchema>;

/** Fila completa de creative_profiles, tal como la devuelve Supabase. */
export const CreativeProfileSchema = CreativeProfileInputSchema.extend({
  id: z.string().uuid(),
  created_at: z.string(),
  updated_at: z.string(),
});
export type CreativeProfile = z.infer<typeof CreativeProfileSchema>;

/**
 * ZAI-28 · RF-CRE-01 · Portafolio del creativo (tabla creative_posts).
 * Los valores deben coincidir con 0004_creative_posts.sql.
 */
export const PostCategory = z.enum(["render", "plano", "idea"]);
export type PostCategory = z.infer<typeof PostCategory>;

export const CATEGORY_LABEL: Record<PostCategory, string> = {
  render: "Render",
  plano: "Plano",
  idea: "Idea",
};

export const MAX_POST_IMAGES = 10;

/** Lo que manda el formulario de una publicación del portafolio. */
export const CreativePostInputSchema = z.object({
  title: z.string().trim().min(3, "El título debe tener al menos 3 letras").max(120),
  description: z.string().max(2000, "Máximo 2000 caracteres").nullable().default(null),
  category: PostCategory,
  images: z
    .array(z.string().url())
    .min(1, "Sube al menos una imagen")
    .max(MAX_POST_IMAGES, `Máximo ${MAX_POST_IMAGES} imágenes`),
  // Opcionales: sirven para sugerir el diseño en propiedades parecidas (ZAI-30)
  property_type: PropertyType.nullable().default(null),
  city: z.string().trim().min(2, "Escribe la ciudad completa").max(80).nullable().default(null),
});
export type CreativePostInput = z.infer<typeof CreativePostInputSchema>;

/** Fila completa de creative_posts, tal como la devuelve Supabase. */
export const CreativePostSchema = CreativePostInputSchema.extend({
  id: z.string().uuid(),
  creative_id: z.string().uuid(),
  created_at: z.string(),
  updated_at: z.string(),
});
export type CreativePost = z.infer<typeof CreativePostSchema>;
