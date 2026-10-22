import { z } from "zod";

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
