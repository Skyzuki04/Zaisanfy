import type { Property } from "@zaisanfy/schemas";
import { POST_SELECT, type PostWithCreative } from "./posts";
import { supabase } from "./supabase";

export type SuggestionRule = "ambos" | "tipo" | "ciudad";
export const SUGGESTION_RULE: SuggestionRule = "ambos";
export const MAX_SUGGESTIONS = 6;

export async function getSuggestedPosts(property: Property, rule: SuggestionRule = SUGGESTION_RULE): Promise<PostWithCreative[]> {
  const type = property.data.propertyType;
  const city = property.data.location.city.trim();

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

function escapeLike(s: string) {
  return s.replace(/[\\%_]/g, (m) => `\\${m}`);
}
