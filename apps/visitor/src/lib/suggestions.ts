import type { Property } from "@zaisanfy/schemas";
import { POST_SELECT, type PostWithCreative } from "./posts";
import { supabase } from "./supabase";

/**
 * ZAI-30 · RF-VIS-03 · Diseños sugeridos en el detalle de una propiedad.
 *
 * Regla (la decide el PO; se cambia solo aquí):
 * - "ambos": sugiere renders del mismo tipo de propiedad O de la misma ciudad.
 *   Primero los que coinciden en las dos cosas, luego los del mismo tipo y al final los de la ciudad.
 * - "tipo": solo los del mismo tipo de propiedad.
 * - "ciudad": solo los de la misma ciudad.
 * Dentro de cada grupo van primero los más recientes.
 */
export type SuggestionRule = "ambos" | "tipo" | "ciudad";
export const SUGGESTION_RULE: SuggestionRule = "ambos";
export const MAX_SUGGESTIONS = 6;

export async function getSuggestedPosts(property: Property, rule: SuggestionRule = SUGGESTION_RULE): Promise<PostWithCreative[]> {
  const type = property.data.propertyType;
  const city = property.data.location.city.trim();

  // Dos consultas sencillas (en vez de un .or con texto libre) para no tener que escapar la ciudad
  const byType = () =>
    supabase.from("creative_posts").select(POST_SELECT).eq("property_type", type).order("created_at", { ascending: false }).limit(MAX_SUGGESTIONS * 2);
  const byCity = () =>
    supabase.from("creative_posts").select(POST_SELECT).ilike("city", escapeLike(city)).order("created_at", { ascending: false }).limit(MAX_SUGGESTIONS * 2);

  const [t, c] = await Promise.all([rule !== "ciudad" ? byType() : null, rule !== "tipo" ? byCity() : null]);
  const all = new Map<string, PostWithCreative>();
  for (const p of [...((t?.data as PostWithCreative[]) ?? []), ...((c?.data as PostWithCreative[]) ?? [])]) all.set(p.id, p);

  const sameCity = (p: PostWithCreative) => !!p.city && p.city.trim().toLowerCase() === city.toLowerCase();
  const score = (p: PostWithCreative) => (p.property_type === type ? 2 : 0) + (sameCity(p) ? 1 : 0);

  return [...all.values()]
    .sort((a, b) => score(b) - score(a) || b.created_at.localeCompare(a.created_at))
    .slice(0, MAX_SUGGESTIONS);
}

/** En ILIKE, % y _ son comodines: se escapan para que la ciudad se compare tal cual. */
function escapeLike(s: string) {
  return s.replace(/[\\%_]/g, (m) => `\\${m}`);
}
