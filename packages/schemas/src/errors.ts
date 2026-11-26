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

// Dato fuera de rango (23514): qué decir según la regla de la base que saltó
const CHECK_BY_CONSTRAINT: Record<string, string> = {
  properties_title_len: "El título debe tener entre 3 y 120 letras.",
  properties_desc_len: "La descripción es de máximo 2000 caracteres.",
  properties_price: "El precio debe ser mayor a 0.",
  properties_bedrooms: "Las recámaras no pueden ser negativas.",
  properties_bathrooms: "Los baños no pueden ser negativos.",
  properties_area: "Los metros cuadrados deben ser mayores a 0.",
  properties_state_len: "El estado es obligatorio.",
  properties_city_len: "La ciudad es obligatoria.",
  properties_lat: "La latitud va de -90 a 90.",
  properties_lng: "La longitud va de -180 a 180.",
  creative_profiles_service_radius_km_check: "El radio de trabajo va de 1 a 200 km.",
  service_requests_address_check: "Escribe la dirección completa.",
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
  if (code === "23514") {
    const constraint = /constraint "([^"]+)"/.exec(text)?.[1];
    if (constraint && CHECK_BY_CONSTRAINT[constraint]) return CHECK_BY_CONSTRAINT[constraint];
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

export type AuthErrorLike = { code?: string | null; message?: string | null; status?: number | null } | null | undefined;

/**
 * Errores de inicio de sesión y registro (Supabase Auth) en palabras normales.
 * Supabase los manda en inglés ("Email not confirmed", "Password should be at least 6 characters"…);
 * aquí se revisa primero el código y luego el texto, porque las versiones viejas no mandan código.
 */
export function authError(error: AuthErrorLike, fallback = "No pudimos completar la operación. Intenta de nuevo."): string {
  if (!error) return fallback;
  const code = error.code ?? "";
  const m = error.message ?? "";
  if (code === "invalid_credentials" || /invalid login credentials/i.test(m)) return "Correo o contraseña incorrectos.";
  if (code === "email_not_confirmed" || /email not confirmed/i.test(m)) {
    return "Todavía no confirmas tu correo. Abre el correo que te mandamos (revisa también spam) y vuelve a entrar.";
  }
  if (code === "user_already_exists" || code === "email_exists" || /already registered/i.test(m)) return "Ese correo ya tiene una cuenta. Inicia sesión.";
  if (code === "captcha_failed" || /captcha/i.test(m)) return "La verificación de robot falló. Intenta de nuevo.";
  if (code === "user_banned" || /banned/i.test(m)) return "Tu cuenta está suspendida. Escríbenos si crees que es un error.";
  if (code === "weak_password" || /weak|pwned|known to be/i.test(m)) {
    const min = /at least (\d+)/i.exec(m)?.[1];
    return min
      ? `La contraseña debe tener al menos ${min} caracteres.`
      : "Esa contraseña es muy fácil de adivinar. Usa una más larga, con letras y números.";
  }
  if (/password should be at least (\d+)/i.test(m)) return `La contraseña debe tener al menos ${/at least (\d+)/i.exec(m)?.[1]} caracteres.`;
  if (code === "email_address_invalid" || code === "validation_failed" || /unable to validate email|invalid format|invalid email/i.test(m)) {
    return "Escribe un correo válido.";
  }
  if (code.startsWith("over_") || error.status === 429 || /rate limit|too many/i.test(m)) {
    return "Hiciste demasiados intentos seguidos. Espera unos minutos e intenta de nuevo.";
  }
  if (code === "signup_disabled" || /signups not allowed/i.test(m)) return "Por ahora no se pueden crear cuentas nuevas.";
  if (/Failed to fetch|NetworkError|fetch failed/i.test(m)) return "No hay conexión. Revisa tu internet e intenta de nuevo.";
  return fallback;
}

/** Formatos de foto que acepta el preset de Cloudinary. */
export const IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "webp", "heic", "heif"] as const;

/**
 * Revisa el formato por extensión y por tipo. En Windows el navegador manda el tipo vacío
 * para HEIC y a veces para JPG con extensión en mayúsculas, así que la extensión manda.
 */
export function imageFormatError(name: string, type: string): string | null {
  const ext = /\.([a-z0-9]+)$/i.exec(name)?.[1]?.toLowerCase() ?? "";
  if ((IMAGE_EXTENSIONS as readonly string[]).includes(ext)) return null;
  if (!ext && /^image\/(jpe?g|png|webp|hei[cf])$/i.test(type)) return null;
  return `"${name}" no es un formato permitido. Usa una foto JPG, PNG, WEBP o HEIC.`;
}

/** Errores al subir imágenes (Cloudinary) en palabras normales. Si no se reconoce, se agrega el motivo real. */
export function uploadError(message: string | null | undefined): string {
  const m = message ?? "";
  if (/file size too large|too large/i.test(m)) return "La imagen pesa demasiado. Usa una de máximo 10 MB.";
  if (/resolution too high|megapixel|mpixel/i.test(m)) return "La imagen tiene demasiada resolución. Usa una de máximo 25 megapíxeles.";
  if (/upload preset|whitelisted|unsigned|cloud_name|api key|unknown api/i.test(m)) {
    return "El servicio de fotos está mal configurado (preset o nube de Cloudinary). Revisa VITE_CLOUDINARY_CLOUD_NAME y VITE_CLOUDINARY_UPLOAD_PRESET en apps/partner/.env.";
  }
  if (/format|invalid image|unsupported/i.test(m)) {
    // Cloudinary dice qué formato detectó por dentro ("Image file format avif not allowed"), aunque el archivo diga .jpg
    const real = /format (\w+) not allowed/i.exec(m)?.[1]?.toUpperCase();
    return real
      ? `Ese formato no se permite: aunque el nombre diga otra cosa, por dentro el archivo es ${real}. Usa una foto JPG, PNG, WEBP o HEIC.`
      : `Ese formato no se permite. Usa una foto JPG, PNG, WEBP o HEIC. (Detalle: ${m.slice(0, 160)})`;
  }
  if (/Failed to fetch|NetworkError|fetch failed|network|load failed/i.test(m)) return "No hay conexión. Revisa tu internet e intenta de nuevo.";
  if (/rate limit|too many/i.test(m)) return "Subiste muchas fotos seguidas. Espera un minuto e intenta de nuevo.";
  return m ? `No se pudo subir la imagen. Intenta de nuevo. (Detalle: ${m.slice(0, 160)})` : "No se pudo subir la imagen. Intenta de nuevo.";
}
