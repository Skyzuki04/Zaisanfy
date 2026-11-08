// RF-VIS-05: ruta de visitas por las propiedades de Mi Lista (solo servidor)
import type { Property } from "@zaisanfy/schemas";

// Google Maps abre en el navegador hasta 9 paradas intermedias + el destino
export const MAX_STOPS = 10;

export type Point = { lat: number; lng: number } | { address: string };
type Stop = { id: string; title: string; point: Point };
type Matrix = { seconds: number[][]; meters: number[][] }; // fila 0 = punto de salida; columnas = paradas

export type RouteLeg = { id: string; title: string; seconds: number; meters: number };
export type RoutePlan = {
  legs: RouteLeg[];
  totalSeconds: number;
  totalMeters: number;
  mapsUrl: string;
  source: "google" | "estimado";
  skipped: { id: string; title: string }[]; // sin ubicación suficiente para la ruta
};

const hasCoords = (p: Point): p is { lat: number; lng: number } => "lat" in p;
const asText = (p: Point) => (hasCoords(p) ? `${p.lat},${p.lng}` : p.address);

function propertyPoint(p: Property): Point | null {
  const l = p.data.location;
  if (l.lat !== undefined && l.lng !== undefined) return { lat: l.lat, lng: l.lng };
  if (!l.address) return null; // solo la ciudad no basta para llegar
  return { address: [l.address, l.neighborhood, l.city, l.state, "México"].filter(Boolean).join(", ") };
}

// --- Matriz de tiempos con Google Routes API (computeRouteMatrix) ---
const toWaypoint = (p: Point) =>
  hasCoords(p) ? { waypoint: { location: { latLng: { latitude: p.lat, longitude: p.lng } } } } : { waypoint: { address: p.address } };

async function googleMatrix(key: string, origin: Point, stops: Stop[]): Promise<Matrix> {
  const rows = [origin, ...stops.map((s) => s.point)];
  const res = await fetch("https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": key,
      "X-Goog-FieldMask": "originIndex,destinationIndex,duration,distanceMeters,condition",
    },
    body: JSON.stringify({
      origins: rows.map(toWaypoint),
      destinations: stops.map((s) => toWaypoint(s.point)),
      travelMode: "DRIVE",
      languageCode: "es-MX",
      regionCode: "MX",
    }),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`Google Routes respondió ${res.status}`);
  const elements = (await res.json()) as { originIndex: number; destinationIndex: number; duration?: string; distanceMeters?: number; condition?: string }[];
  const seconds = rows.map(() => stops.map(() => Infinity));
  const meters = rows.map(() => stops.map(() => Infinity));
  for (const e of elements) {
    if (e.condition !== "ROUTE_EXISTS") continue;
    seconds[e.originIndex][e.destinationIndex] = Number.parseInt(e.duration ?? "0", 10);
    meters[e.originIndex][e.destinationIndex] = e.distanceMeters ?? 0;
  }
  return { seconds, meters };
}

// --- Sin llave de Google: estimado por línea recta ---
const ROAD_FACTOR = 1.35; // las calles no van en línea recta
const CITY_KMH = 30; // velocidad promedio en ciudad

function haversineMeters(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const rad = (d: number) => (d * Math.PI) / 180;
  const h = Math.sin(rad(b.lat - a.lat) / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(rad(b.lng - a.lng) / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

function estimatedMatrix(origin: { lat: number; lng: number }, stops: { lat: number; lng: number }[]): Matrix {
  const rows = [origin, ...stops];
  const meters = rows.map((a) => stops.map((b) => Math.round(haversineMeters(a, b) * ROAD_FACTOR)));
  const seconds = meters.map((row) => row.map((m) => Math.round(m / ((CITY_KMH * 1000) / 3600))));
  return { seconds, meters };
}

// --- El orden más rápido (Held-Karp: exacto, con 10 paradas son ~100 mil pasos) ---
// La ruta sale del punto de salida, pasa por todas las paradas y termina en la última.
export function bestOrder(seconds: number[][]): number[] | null {
  const n = seconds[0].length;
  if (n === 0) return [];
  const full = (1 << n) - 1;
  const cost: number[][] = Array.from({ length: 1 << n }, () => new Array(n).fill(Infinity));
  const prev: number[][] = Array.from({ length: 1 << n }, () => new Array(n).fill(-1));
  for (let j = 0; j < n; j++) cost[1 << j][j] = seconds[0][j];
  for (let mask = 1; mask <= full; mask++) {
    for (let j = 0; j < n; j++) {
      const c = cost[mask][j];
      if (!(mask & (1 << j)) || c === Infinity) continue;
      for (let k = 0; k < n; k++) {
        if (mask & (1 << k)) continue;
        const next = mask | (1 << k);
        const t = c + seconds[j + 1][k]; // fila j+1 = salir de la parada j
        if (t < cost[next][k]) {
          cost[next][k] = t;
          prev[next][k] = j;
        }
      }
    }
  }
  let last = -1;
  for (let j = 0; j < n; j++) if (cost[full][j] < (last < 0 ? Infinity : cost[full][last])) last = j;
  if (last < 0) return null;
  const order: number[] = [];
  for (let mask = full, j = last; j >= 0; ) {
    order.push(j);
    const p = prev[mask][j];
    mask &= ~(1 << j);
    j = p;
  }
  return order.reverse();
}

function mapsUrl(origin: Point, ordered: Stop[]) {
  const sp = new URLSearchParams({ api: "1", origin: asText(origin), destination: asText(ordered[ordered.length - 1].point), travelmode: "driving" });
  if (ordered.length > 1) sp.set("waypoints", ordered.slice(0, -1).map((s) => asText(s.point)).join("|"));
  return `https://www.google.com/maps/dir/?${sp.toString()}`;
}

export class RouteError extends Error {}

export async function planRoute(origin: Point, properties: Property[], googleKey?: string): Promise<RoutePlan> {
  const source = googleKey ? "google" : "estimado";
  const skipped: RoutePlan["skipped"] = [];
  const stops: Stop[] = [];
  for (const p of properties) {
    const point = propertyPoint(p);
    // sin Google solo se pueden usar coordenadas
    if (point && (googleKey || hasCoords(point))) stops.push({ id: p.id, title: p.data.title, point });
    else skipped.push({ id: p.id, title: p.data.title });
  }
  if (stops.length === 0) throw new RouteError("Ninguna de las propiedades elegidas tiene ubicación exacta para trazar la ruta.");
  if (!googleKey && !hasCoords(origin)) {
    throw new RouteError("Para salir de una dirección escrita hace falta Google Maps. Usa tu ubicación actual.");
  }

  const matrix = googleKey
    ? await googleMatrix(googleKey, origin, stops)
    : estimatedMatrix(origin as { lat: number; lng: number }, stops.map((s) => s.point as { lat: number; lng: number }));

  const order = bestOrder(matrix.seconds);
  if (!order) throw new RouteError("No encontramos un camino en auto entre tu punto de salida y estas propiedades.");

  const legs: RouteLeg[] = order.map((k, i) => {
    const from = i === 0 ? 0 : order[i - 1] + 1;
    return { id: stops[k].id, title: stops[k].title, seconds: matrix.seconds[from][k], meters: matrix.meters[from][k] };
  });
  return {
    legs,
    totalSeconds: legs.reduce((s, l) => s + l.seconds, 0),
    totalMeters: legs.reduce((s, l) => s + l.meters, 0),
    mapsUrl: mapsUrl(origin, order.map((k) => stops[k])),
    source,
    skipped,
  };
}
