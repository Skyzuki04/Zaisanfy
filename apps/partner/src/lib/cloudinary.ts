import { imageFormatError, uploadError } from "@zaisanfy/schemas";

const cloudName = import.meta.env.VITE_CLOUDINARY_CLOUD_NAME;
const uploadPreset = import.meta.env.VITE_CLOUDINARY_UPLOAD_PRESET;

export const MAX_BYTES = 10 * 1024 * 1024;
export const MAX_MEGAPIXELS = 25;

export async function uploadImage(file: File): Promise<string> {
  if (!cloudName || !uploadPreset) {
    throw new Error("Faltan VITE_CLOUDINARY_CLOUD_NAME o VITE_CLOUDINARY_UPLOAD_PRESET en apps/partner/.env");
  }
  const body = new FormData();
  body.append("file", file);
  body.append("upload_preset", uploadPreset);
  let res: Response;
  try {
    res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, { method: "POST", body });
  } catch (e) {
    console.error("[Cloudinary] sin respuesta", e);
    throw new Error(uploadError((e as Error).message));
  }
  const json = await res.json().catch(() => null);
  // Cloudinary contesta en inglés ("File size too large", "Invalid image file"): se traduce antes de mostrarlo
  if (!res.ok || !json?.secure_url) {
    console.error("[Cloudinary]", res.status, json);
    throw new Error(uploadError(json?.error?.message ?? `HTTP ${res.status}`));
  }
  return json.secure_url as string;
}

const isHeic = (file: File) => /\.(heic|heif)$/i.test(file.name) || /hei[cf]/i.test(file.type);

/** Medidas de la imagen; null si el navegador no la puede abrir (por ejemplo HEIC en Chrome o Edge). */
export function readImageSize(file: File): Promise<{ width: number; height: number } | null> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
      URL.revokeObjectURL(url);
    };
    img.onerror = () => {
      resolve(null);
      URL.revokeObjectURL(url);
    };
    img.src = url;
  });
}

/** Nunca lanza: regresa el mensaje de error o null si la foto se puede subir. */
export async function checkImage(file: File): Promise<string | null> {
  const fmt = imageFormatError(file.name, file.type);
  if (fmt) return fmt;
  if (file.size > MAX_BYTES) return `"${file.name}" pesa más de 10 MB`;
  const size = await readImageSize(file);
  // HEIC: el navegador no lo abre, pero Cloudinary sí; el límite de megapíxeles lo revisa Cloudinary
  if (!size) return isHeic(file) ? null : `"${file.name}" está dañada o no es una imagen válida`;
  if ((size.width * size.height) / 1_000_000 > MAX_MEGAPIXELS) return `"${file.name}" pasa de ${MAX_MEGAPIXELS} megapíxeles`;
  return null;
}

export async function check360(file: File): Promise<string | null> {
  const basic = await checkImage(file);
  if (basic) return basic;
  const size = await readImageSize(file);
  if (!size) return "No puedo medir esta foto 360 (HEIC). Expórtala como JPG para revisar que sea 2:1.";
  const ratio = size.width / size.height;
  if (Math.abs(ratio - 2) > 0.02) {
    return `La foto 360 debe ser 2:1 (por ejemplo 6000 × 3000). Esta mide ${size.width} × ${size.height}.`;
  }
  return null;
}
