import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error("Faltan VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY en apps/admin/.env");
}

// Sesión aparte de la Consola (otra llave de almacenamiento), así entrar aquí no toca la sesión de socios
export const supabase = createClient(url, anonKey, { auth: { storageKey: "zaisanfy-admin-core" } });
