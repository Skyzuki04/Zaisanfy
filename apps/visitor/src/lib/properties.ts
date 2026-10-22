import type { Property } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

/** Una propiedad publicada (RLS no deja ver las demás sin sesión). */
export async function getPublishedProperty(id: string): Promise<Property | null> {
  // Un id que no es uuid haría fallar la consulta: se trata como "no existe"
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await supabase.from("properties").select("*").eq("id", id).eq("status", "published").maybeSingle();
  return (data as Property) ?? null;
}

/** Portada primero y después el resto de la galería, sin repetir. */
export function orderedPhotos(p: Property): string[] {
  const { coverUrl, gallery } = p.data.media;
  return coverUrl ? [coverUrl, ...gallery.filter((u) => u !== coverUrl)] : gallery;
}
