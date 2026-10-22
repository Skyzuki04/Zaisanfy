import { cache } from "react";
import type { CreativePost, CreativeProfile } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

/** Publicación con los datos del creativo que la subió (para la tarjeta y el enlace al perfil). */
export type PostWithCreative = CreativePost & {
  creative: Pick<CreativeProfile, "id" | "display_name" | "avatar_url">;
};

export const POST_SELECT = "*, creative:creative_profiles(id, display_name, avatar_url)";

const isUuid = (id: string) => /^[0-9a-f-]{36}$/i.test(id);

/** ZAI-28 · Portafolio de un creativo, de lo más nuevo a lo más viejo. */
export async function getCreativePosts(creativeId: string): Promise<PostWithCreative[]> {
  if (!isUuid(creativeId)) return [];
  const { data } = await supabase
    .from("creative_posts")
    .select(POST_SELECT)
    .eq("creative_id", creativeId)
    .order("created_at", { ascending: false })
    .limit(100);
  return (data as PostWithCreative[]) ?? [];
}

/** ZAI-28 · Una publicación del portafolio (RLS: cualquiera la puede leer). */
export const getPost = cache(async (id: string): Promise<PostWithCreative | null> => {
  if (!isUuid(id)) return null;
  const { data } = await supabase.from("creative_posts").select(POST_SELECT).eq("id", id).maybeSingle();
  return (data as PostWithCreative) ?? null;
});
