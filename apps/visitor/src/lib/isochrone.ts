// ZAI-38 · GEO-01: zona a la que se llega en X minutos desde un punto (solo servidor).
// La llave de Mapbox se queda aquí: nunca lleva NEXT_PUBLIC_ y nunca llega al navegador.

export const MINUTES = [10, 20, 30] as const;
export type Minutes = (typeof MINUTES)[number];
export type LatLng = { lat: number; lng: number };

// GeoJSON: [lng, lat] (primero longitud, como lo piden Mapbox y PostGIS)
export type Zone =
  | { type: "Polygon"; coordinates: number[][][] }
  | { type: "MultiPolygon"; coordinates: number[][][][] };

export type Isochrone = {
  center: LatLng;
  minutes: Minutes;
  zone: Zone;
  source: "mapbox" | "estimado";
};

// --- Con llave: Mapbox Isochrone API ---
// https://docs.mapbox.com/api/navigation/isochrone/
async function mapboxZone(token: string, c: LatLng, minutes: Minutes): Promise<Zone> {
  const url = new URL(`https://api.mapbox.com/isochrone/v1/mapbox/driving/${c.lng},${c.lat}`);
  url.searchParams.set("contours_minutes", String(minutes));
  url.searchParams.set("polygons", "true"); // zona rellena, no solo la orilla
  url.searchParams.set("denoise", "1"); // quita islitas sueltas
  url.searchParams.set("generalize", "30"); // simplifica la orilla (metros): menos puntos, misma zona
  url.searchParams.set("access_token", token);

  // La misma zona sirve todo el día: Next guarda la respuesta 24 h y no gasta otra llamada
  const res = await fetch(url, { next: { revalidate: 86400 } });
  if (!res.ok) throw new Error(`Mapbox respondió ${res.status}`);
  const json = (await res.json()) as { features?: { geometry?: Zone }[] };
  const geometry = json.features?.[0]?.geometry;
  if (!geometry || (geometry.type !== "Polygon" && geometry.type !== "MultiPolygon")) {
    throw new Error("Mapbox no regresó una zona");
  }
  return geometry;
}

// --- Sin llave: círculo aproximado (mismos supuestos que la ruta de Mi Lista) ---
const ROAD_FACTOR = 1.35; // las calles no van en línea recta
const CITY_KMH = 30; // velocidad promedio en ciudad

export function estimatedZone(c: LatLng, minutes: Minutes, sides = 48): Zone {
  const radiusM = ((CITY_KMH * 1000) / 60) * minutes / ROAD_FACTOR;
  const dLat = radiusM / 111_320; // metros por grado de latitud
  const dLng = radiusM / (111_320 * Math.cos((c.lat * Math.PI) / 180));
  const ring: number[][] = [];
  for (let i = 0; i < sides; i++) {
    const a = (2 * Math.PI * i) / sides;
    ring.push([round6(c.lng + dLng * Math.cos(a)), round6(c.lat + dLat * Math.sin(a))]);
  }
  ring.push(ring[0]); // GeoJSON cierra el polígono repitiendo el primer punto
  return { type: "Polygon", coordinates: [ring] };
}

const round6 = (n: number) => Math.round(n * 1e6) / 1e6;

export async function getIsochrone(center: LatLng, minutes: Minutes, token = process.env.MAPBOX_ACCESS_TOKEN): Promise<Isochrone> {
  if (token) {
    try {
      return { center, minutes, zone: await mapboxZone(token, center, minutes), source: "mapbox" };
    } catch (e) {
      // Si Mapbox falla, la búsqueda sigue con la zona aproximada (y se avisa en pantalla)
      console.error("isocrona", e);
    }
  }
  return { center, minutes, zone: estimatedZone(center, minutes), source: "estimado" };
}
