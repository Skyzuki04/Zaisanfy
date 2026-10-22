import { createClient } from "@supabase/supabase-js";

// Llaves públicas (anon). Van en apps/partner/.env (ver .env.example).
const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error("Faltan VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY en apps/partner/.env");
}

export const supabase = createClient(url, anonKey);
