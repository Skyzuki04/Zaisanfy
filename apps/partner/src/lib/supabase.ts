import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error("Faltan VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY en apps/partner/.env");
}

export const supabase = createClient(url, anonKey);

// RF-ADM-01: si un admin entró como este usuario (impersonate), la Consola lo avisa mientras dure la pestaña
const KEY = "zaisanfy-como-admin";
try {
  if (new URLSearchParams(window.location.search).has("como_admin")) sessionStorage.setItem(KEY, "1");
} catch {
  /* sin sessionStorage no hay aviso */
}
export const isImpersonating = () => {
  try {
    return sessionStorage.getItem(KEY) === "1";
  } catch {
    return false;
  }
};
export const endImpersonation = () => {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    /* nada */
  }
};
