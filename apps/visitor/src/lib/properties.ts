import { cache } from "react";
import { PROPERTY_SELECT, toProperty, type Property, type PropertyRow } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

export const getPublishedProperty = cache(async (id: string): Promise<Property | null> => {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await supabase.from("properties").select(PROPERTY_SELECT).eq("id", id).eq("status", "published").maybeSingle();
  return data ? toProperty(data as unknown as PropertyRow) : null;
});

export { orderedPhotos } from "./photos";
