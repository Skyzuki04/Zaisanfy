import { cache } from "react";
import { PostCategory, type CreativePost, type CreativeProfile } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

export type PostWithCreative = CreativePost & {
  creative: Pick<CreativeProfile, "id" | "display_name" | "avatar_url">;
};

export const POST_SELECT = "*, creative:creative_profiles(id, display_name, avatar_url)";

const isUuid = (id: string) => /^[0-9a-f-]{36}$/i.test(id);

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

export const getPost = cache(async (id: string): Promise<PostWithCreative | null> => {
  if (!isUuid(id)) return null;
  const { data } = await supabase.from("creative_posts").select(POST_SELECT).eq("id", id).maybeSingle();
  return (data as PostWithCreative) ?? null;
});

export const WALL_PAGE_SIZE = 12;

export type WallFilters = { page: number; category: PostCategory | null };

export function parseWallFilters(sp: Record<string, string | string[] | undefined>): WallFilters {
  const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
  const page = Number.parseInt(one(sp.page) ?? "1", 10);
  const category = PostCategory.safeParse(one(sp.categoria));
  return { page: Number.isFinite(page) && page > 0 ? Math.min(page, 1000) : 1, category: category.success ? category.data : null };
}

export async function getWall({ page, category }: WallFilters): Promise<{ posts: PostWithCreative[]; total: number }> {
  const from = (page - 1) * WALL_PAGE_SIZE;
  let q = supabase
    .from("creative_posts")
    .select(POST_SELECT, { count: "exact" })
    .order("created_at", { ascending: false })
    .order("id")
    .range(from, from + WALL_PAGE_SIZE - 1);
  if (category) q = q.eq("category", category);
  const { data, count, error } = await q;
  if (error) return { posts: [], total: count ?? 0 };
  return { posts: (data as PostWithCreative[]) ?? [], total: count ?? 0 };
}
