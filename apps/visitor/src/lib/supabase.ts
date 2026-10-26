import { createClient } from "@supabase/supabase-js";

// Llaves públicas (anon). Van en apps/visitor/.env.local (ver .env.example).
// Con la llave anon, RLS solo deja leer lo público (propiedades publicadas).
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error("Faltan NEXT_PUBLIC_SUPABASE_URL o NEXT_PUBLIC_SUPABASE_ANON_KEY en apps/visitor/.env.local");
}

export const supabase = createClient(url, anonKey);
