/** URL pública del Escaparate (para canonical, sitemap y JSON-LD). En Vercel: NEXT_PUBLIC_SITE_URL. */
export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000").replace(/\/$/, "");
