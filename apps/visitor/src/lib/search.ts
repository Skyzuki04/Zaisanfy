import { PropertyType, Operation, PROPERTY_SELECT, toProperty, type Property, type PropertyRow } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

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

export function parseFilters(params: Params): Filters {
  const tipo = PropertyType.safeParse(one(params.tipo));
  const operacion = Operation.safeParse(one(params.operacion));
  return {
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
  let q = supabase.from("properties").select(PROPERTY_SELECT).eq("status", "published");
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
