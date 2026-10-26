/**
 * ZAI-26 · RNF-PERF-01 · Fotos optimizadas desde el CDN de Cloudinary.
 * Agrega transformaciones a la URL guardada: formato WebP (f_webp), calidad automática (q_auto)
 * y ancho máximo (w_, c_limit) para no bajar fotos más grandes de lo que se ven.
 * Las URLs que no son de Cloudinary se regresan igual.
 */
export function cld(url: string, width?: number): string {
  const marker = "/image/upload/";
  if (!url.includes("res.cloudinary.com") || !url.includes(marker)) return url;
  const t = ["f_webp", "q_auto", width ? `w_${width}` : null, width ? "c_limit" : null].filter(Boolean).join(",");
  const [base, rest] = url.split(marker);
  // Si la URL ya trae transformaciones (por ejemplo f_auto), no se duplican
  if (/^[a-z]_[^/]*\//.test(rest) && !/^v\d+\//.test(rest)) return url;
  return `${base}${marker}${t}/${rest}`;
}
