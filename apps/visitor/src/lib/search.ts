import type { Property } from "@zaisanfy/schemas";
import { PropertyType, Operation } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

/**
 * ZAI-24 · RF-VIS-01 · Buscador por ubicación, precio y tipo.
 * Los filtros viven en la URL (?ubicacion=&tipo=&operacion=&min=&max=) para poder compartir la búsqueda.
 */
export type Filters = {
  ubicacion?: string;
  tipo?: PropertyType;
  operacion?: Operation;
  min?: number;
  max?: number;
};

type Params = Record<string, string | string[] | undefined>;

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v)?.trim() || undefined;
const money = (v: string | undefined) => {
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) && n >= 0 ? n : undefined;
};

/** Lee y limpia los filtros de la URL. Lo que no es válido se ignora. */
export function parseFilters(params: Params): Filters {
  const tipo = PropertyType.safeParse(one(params.tipo));
  const operacion = Operation.safeParse(one(params.operacion));
  return {
    // Se quitan caracteres que tienen significado especial en los filtros de PostgREST
    ubicacion: one(params.ubicacion)?.replace(/[,()*%\\.:]/g, " ").trim().slice(0, 60) || undefined,
    tipo: tipo.success ? tipo.data : undefined,
    operacion: operacion.success ? operacion.data : undefined,
    min: money(one(params.min)),
    max: money(one(params.max)),
  };
}

export function hasFilters(f: Filters) {
  return Object.values(f).some((v) => v !== undefined);
}

export async function searchProperties(f: Filters): Promise<Property[]> {
  let q = supabase.from("properties").select("*").eq("status", "published");
  if (f.ubicacion) {
    const like = `*${f.ubicacion}*`;
    q = q.or(
      [
        `data->location->>city.ilike.${like}`,
        `data->location->>state.ilike.${like}`,
        `data->location->>neighborhood.ilike.${like}`,
      ].join(",")
    );
  }
  if (f.tipo) q = q.eq("data->>propertyType", f.tipo);
  if (f.operacion) q = q.eq("data->>operation", f.operacion);
  // data->price es número dentro del JSONB: la comparación es numérica
  if (f.min !== undefined) q = q.gte("data->price", f.min);
  if (f.max !== undefined) q = q.lte("data->price", f.max);
  const { data, error } = await q.order("created_at", { ascending: false }).limit(60);
  if (error) throw new Error(error.message);
  return (data as Property[]) ?? [];
}
