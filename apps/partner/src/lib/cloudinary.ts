/**
 * ZAI-22 · Subida directa a Cloudinary con el upload preset "unsigned".
 * La foto va del navegador a Cloudinary; en Supabase solo se guarda la URL.
 */
const cloudName = import.meta.env.VITE_CLOUDINARY_CLOUD_NAME;
const uploadPreset = import.meta.env.VITE_CLOUDINARY_UPLOAD_PRESET;

// Límites del plan Free de Cloudinary
export const MAX_BYTES = 10 * 1024 * 1024; // 10 MB por imagen
export const MAX_MEGAPIXELS = 25;

export async function uploadImage(file: File): Promise<string> {
  if (!cloudName || !uploadPreset) {
    throw new Error("Faltan VITE_CLOUDINARY_CLOUD_NAME o VITE_CLOUDINARY_UPLOAD_PRESET en apps/partner/.env");
  }
  const body = new FormData();
  body.append("file", file);
  body.append("upload_preset", uploadPreset);
  const res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, { method: "POST", body });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.message ?? "No se pudo subir la imagen");
  return json.secure_url as string;
}

/** Lee el ancho y alto real de una imagen antes de subirla. */
export function readImageSize(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
      URL.revokeObjectURL(url);
    };
    img.onerror = () => {
      reject(new Error("El archivo no es una imagen válida"));
      URL.revokeObjectURL(url);
    };
    img.src = url;
  });
}

/** Revisa tamaño y megapíxeles. Devuelve el error o null. */
export async function checkImage(file: File): Promise<string | null> {
  if (!file.type.startsWith("image/")) return `"${file.name}" no es una imagen`;
  if (file.size > MAX_BYTES) return `"${file.name}" pesa más de 10 MB`;
  const { width, height } = await readImageSize(file);
  if ((width * height) / 1_000_000 > MAX_MEGAPIXELS) return `"${file.name}" pasa de ${MAX_MEGAPIXELS} megapíxeles`;
  return null;
}

/** Una foto 360 equirectangular mide el doble de ancho que de alto (2:1). Se acepta 1 % de diferencia. */
export async function check360(file: File): Promise<string | null> {
  const basic = await checkImage(file);
  if (basic) return basic;
  const { width, height } = await readImageSize(file);
  const ratio = width / height;
  if (Math.abs(ratio - 2) > 0.02) {
    return `La foto 360 debe ser 2:1 (por ejemplo 6000 × 3000). Esta mide ${width} × ${height}.`;
  }
  return null;
}
