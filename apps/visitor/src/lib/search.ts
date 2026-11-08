import { PropertyType, Operation, PROPERTY_SELECT, toProperty, type Property, type PropertyRow } from "@zaisanfy/schemas";
import { supabase } from "./supabase";
import { MINUTES, type LatLng, type Minutes, type Zone } from "./isochrone";

export type Filters = {
  ubicacion?: string;
  tipo?: PropertyType;
  operacion?: Operation;
  min?: number;
  max?: number;
  // ZAI-38: búsqueda por isocronas (?cerca=lat,lng&tiempo=20)
  cerca?: LatLng;
  tiempo?: Minutes;
};

type Params = Record<string, string | string[] | undefined>;

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)?.trim() || undefined;
const money = (v: string | undefined) => {
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) && n >= 0 ? n : undefined;
};

// "19.4326,-99.1332" → { lat, lng }. Se redondea a 3 decimales (~100 m): da igual para la zona
// y así puntos casi iguales reusan la misma respuesta guardada de Mapbox.
export function parsePoint(v: string | undefined): LatLng | undefined {
  const m = v?.match(/^\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$/);
  if (!m) return undefined;
  const lat = Math.round(Number(m[1]) * 1000) / 1000;
  const lng = Math.round(Number(m[2]) * 1000) / 1000;
  return Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : undefined;
}

export function parseFilters(params: Params): Filters {
  const tipo = PropertyType.safeParse(one(params.tipo));
  const operacion = Operation.safeParse(one(params.operacion));
  const cerca = parsePoint(one(params.cerca));
  const tiempo = MINUTES.find((m) => String(m) === one(params.tiempo));
  return {
    ubicacion: one(params.ubicacion)?.replace(/[,()*%\\.:]/g, " ").trim().slice(0, 60) || undefined,
    tipo: tipo.success ? tipo.data : undefined,
    operacion: operacion.success ? operacion.data : undefined,
    min: money(one(params.min)),
    max: money(one(params.max)),
    cerca,
    tiempo: cerca ? (tiempo ?? 20) : undefined,
  };
}

// Filtros → query string (para armar enlaces sin perder lo que el visitante ya eligió)
export function toQuery(f: Filters) {
  const sp = new URLSearchParams();
  if (f.ubicacion) sp.set("ubicacion", f.ubicacion);
  if (f.tipo) sp.set("tipo", f.tipo);
  if (f.operacion) sp.set("operacion", f.operacion);
  if (f.min !== undefined) sp.set("min", String(f.min));
  if (f.max !== undefined) sp.set("max", String(f.max));
  if (f.cerca) sp.set("cerca", `${f.cerca.lat},${f.cerca.lng}`);
  if (f.tiempo) sp.set("tiempo", String(f.tiempo));
  return sp.toString();
}

export function hasFilters(f: Filters) {
  return Object.values(f).some((v) => v !== undefined);
}

// Con zona, la base de datos (PostGIS) regresa solo las propiedades dentro; los demás filtros se suman igual
export async function searchProperties(f: Filters, zone?: Zone): Promise<Property[]> {
  let q = (zone ? supabase.rpc("properties_in_zone", { zone }).select(PROPERTY_SELECT) : supabase.from("properties").select(PROPERTY_SELECT))
    .eq("status", "published");
  if (f.ubicacion) {
    const like = `*${f.ubicacion}*`;
    q = q.or(
      [
        `city.ilike.${like}`,
        `state.ilike.${like}`,
        `neighborhood.ilike.${like}`,
      ].join(",")
    );
  }
  if (f.tipo) q = q.eq("property_type", f.tipo);
  if (f.operacion) q = q.eq("operation", f.operacion);
  if (f.min !== undefined) q = q.gte("price", f.min);
  if (f.max !== undefined) q = q.lte("price", f.max);
  const { data, error } = await q.order("created_at", { ascending: false }).limit(60);
  if (error) throw new Error(error.message);
  return ((data as unknown as PropertyRow[]) ?? []).map(toProperty);
}
