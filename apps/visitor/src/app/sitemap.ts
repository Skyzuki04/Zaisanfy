import type { MetadataRoute } from "next";
import { supabase } from "@/lib/supabase";
import { SITE_URL } from "@/lib/site";

// ZAI-25 · Sitemap con todas las propiedades publicadas, para que Google las encuentre.
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const { data } = await supabase.from("properties").select("id, updated_at").eq("status", "published").limit(5000);
  return [
    { url: `${SITE_URL}/`, changeFrequency: "daily", priority: 1 },
    ...(data ?? []).map((p) => ({ url: `${SITE_URL}/propiedad/${p.id}`, lastModified: p.updated_at, changeFrequency: "weekly" as const, priority: 0.8 })),
  ];
}
