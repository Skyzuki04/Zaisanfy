"use client";

import type { SupabaseClient } from "@supabase/supabase-js";

let client: Promise<SupabaseClient> | null = null;

export function browserSupabase(): Promise<SupabaseClient> {
  client ??= import("@supabase/supabase-js").then(({ createClient }) =>
    createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
      auth: { persistSession: true, autoRefreshToken: true, storageKey: "zaisanfy-visitor-auth" },
    }),
  );
  return client;
}
