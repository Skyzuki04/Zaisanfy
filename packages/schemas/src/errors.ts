// Errores de la base en palabras normales. Así nunca le sale al usuario un "duplicate key value violates…".
// Los códigos son los de Postgres (https://www.postgresql.org/docs/current/errcodes-appendix.html)
// más los nuestros (ZA…), que se lanzan desde los triggers de Supabase.

export type DbError = { code?: string | null; message?: string | null; details?: string | null; hint?: string | null } | null | undefined;

// Dato repetido (23505): qué decir según la restricción que saltó
const DUPLICATE_BY_CONSTRAINT: Record<string, string> = {
  bookmarks_pkey: "Esta propiedad ya está en tu lista.",
  property_photos_property_id_kind_position_key: "Ya hay una foto en esa posición. Vuelve a ordenar las fotos e intenta de nuevo.",
  property_photos_one_panorama: "Esta propiedad ya tiene su foto 360°. Quita la anterior para subir otra.",
  post_images_post_id_position_key: "Ya hay una imagen en esa posición. Vuelve a ordenar las imágenes e intenta de nuevo.",
  creative_profiles_pkey: "Ya tienes un perfil de creativo. Edítalo desde “Mi perfil”.",
  subscriptions_one_live: "Ya tienes un plan activo. Cámbialo desde “Mi plan”.",
  lead_unlocks_pkey: "Este contacto ya estaba desbloqueado. No se te cobró de nuevo.",
  service_requests_one_open: "Ya tienes un fotógrafo pedido para esta propiedad.",
};

// Mensajes en inglés que Postgres arma solo: esos nunca se muestran tal cual
const POSTGRES_ENGLISH = /^(permission denied|new row violates|duplicate key|null value|insert or update|update or delete|value too long|invalid input)/i;

const BY_CODE: Record<string, string> = {
  "23505": "Ese dato ya existe. Revisa que no lo hayas guardado antes.",
  "23503": "Falta un dato relacionado o ya no existe. Recarga la página e intenta de nuevo.",
  "23502": "Falta llenar un dato obligatorio.",
  "23514": "Algún dato no es válido. Revisa los campos marcados.",
  "22001": "Uno de los textos es demasiado largo.",
  "22P02": "Uno de los datos no tiene el formato correcto.",
  "42501": "No tienes permiso para hacer esto.",
  PGRST116: "No encontramos lo que buscas o no es tuyo.",
  PGRST301: "Tu sesión expiró. Vuelve a entrar.",
};

/** Mensaje para mostrar al usuario a partir de un error de Supabase. */
export function friendlyError(error: DbError, fallback = "Algo salió mal. Intenta de nuevo."): string {
  if (!error) return fallback;
  const code = error.code ?? "";
  const text = `${error.message ?? ""} ${error.details ?? ""}`;

  // Nuestros errores (ZA001 límite del plan, etc.) ya vienen en español y con su sugerencia
  if (code.startsWith("ZA")) return [error.message, error.hint].filter(Boolean).join(" ");

  if (code === "23505") {
    const constraint = /constraint "([^"]+)"/.exec(text)?.[1];
    return (constraint && DUPLICATE_BY_CONSTRAINT[constraint]) ?? BY_CODE["23505"];
  }
  // Mensajes que ya escribimos en español desde la base (raise exception '...')
  if ((code === "P0001" || code === "42501") && error.message && !POSTGRES_ENGLISH.test(error.message)) return error.message;
  if (BY_CODE[code]) return BY_CODE[code];
  if (/Failed to fetch|NetworkError|fetch failed/i.test(text)) return "No hay conexión. Revisa tu internet e intenta de nuevo.";
  if (/JWT expired/i.test(text)) return BY_CODE.PGRST301;
  return fallback;
}

/** true si el error es un dato repetido (23505). */
export const isDuplicate = (error: DbError) => error?.code === "23505";

/** true si el error es el límite del plan (ZA001). */
export const isPlanLimit = (error: DbError) => error?.code === "ZA001";
