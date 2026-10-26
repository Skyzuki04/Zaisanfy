import type { MetadataRoute } from "next";
import { supabase } from "@/lib/supabase";
import { SITE_URL } from "@/lib/site";

// ZAI-25 · Sitemap con todas las propiedades publicadas, para que Google las encuentre.
// ZAI-28 · También los perfiles de creativos y sus publicaciones.
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [{ data }, { data: creatives }, { data: posts }] = await Promise.all([
    supabase.from("properties").select("id, updated_at").eq("status", "published").limit(5000),
    supabase.from("creative_profiles").select("id, updated_at").limit(5000),
    supabase.from("creative_posts").select("id, updated_at").limit(5000),
  ]);
  return [
    { url: `${SITE_URL}/`, changeFrequency: "daily", priority: 1 },
    ...(data ?? []).map((p) => ({ url: `${SITE_URL}/propiedad/${p.id}`, lastModified: p.updated_at, changeFrequency: "weekly" as const, priority: 0.8 })),
    ...(creatives ?? []).map((c) => ({ url: `${SITE_URL}/creativos/${c.id}`, lastModified: c.updated_at, changeFrequency: "weekly" as const, priority: 0.5 })),
    ...(posts ?? []).map((p) => ({ url: `${SITE_URL}/publicaciones/${p.id}`, lastModified: p.updated_at, changeFrequency: "monthly" as const, priority: 0.5 })),
  ];
}
