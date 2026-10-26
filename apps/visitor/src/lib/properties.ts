import { cache } from "react";
import type { Property } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

/** Una propiedad publicada (RLS no deja ver las demás sin sesión). cache(): una sola consulta por petición. */
export const getPublishedProperty = cache(async (id: string): Promise<Property | null> => {
  // Un id que no es uuid haría fallar la consulta: se trata como "no existe"
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await supabase.from("properties").select("*").eq("id", id).eq("status", "published").maybeSingle();
  return (data as Property) ?? null;
});

// Vive en photos.ts para poder usarla también en componentes del navegador (Mi Lista)
export { orderedPhotos } from "./photos";
