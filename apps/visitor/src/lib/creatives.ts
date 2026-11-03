import { cache } from "react";
import type { CreativeProfile } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

const isUuid = (id: string) => /^[0-9a-f-]{36}$/i.test(id);

export const getCreativeProfile = cache(async (id: string): Promise<CreativeProfile | null> => {
  if (!isUuid(id)) return null;
  const { data } = await supabase.from("creative_profiles").select("*").eq("id", id).maybeSingle();
  return (data as CreativeProfile) ?? null;
});
