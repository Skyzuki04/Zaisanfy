"use client";

import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * ZAI-31 · Cliente de Supabase para el navegador (sesión del visitante para "Mi Lista").
 * Las páginas públicas siguen usando lib/supabase.ts en el servidor, sin sesión, para no perder el caché (ISR).
 * La librería se descarga aparte (import dinámico) para no frenar la primera carga (ZAI-26).
 */
let client: Promise<SupabaseClient> | null = null;

export function browserSupabase(): Promise<SupabaseClient> {
  client ??= import("@supabase/supabase-js").then(({ createClient }) =>
    createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
      auth: { persistSession: true, autoRefreshToken: true, storageKey: "zaisanfy-visitor-auth" },
    }),
  );
  return client;
}
