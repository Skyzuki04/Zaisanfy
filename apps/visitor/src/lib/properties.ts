import { cache } from "react";
import type { Property } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

export const getPublishedProperty = cache(async (id: string): Promise<Property | null> => {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await supabase.from("properties").select("*").eq("id", id).eq("status", "published").maybeSingle();
  return (data as Property) ?? null;
});

export { orderedPhotos } from "./photos";
