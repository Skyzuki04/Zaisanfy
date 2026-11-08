import { PROPERTY_SELECT, toProperty, type Property, type PropertyRow } from "@zaisanfy/schemas";
import type { Filters } from "./search";
import { supabase } from "./supabase";

export type Sponsored = { adId: string; property: Property };
type Placement = "buscador" | "muro";

const shuffle = <T,>(list: T[]) => {
  const a = [...list];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

// Anuncios vigentes (ad_is_live: pagados, publicados y dentro de sus fechas), en orden al azar para rotarlos
export async function getSponsored(placement: Placement, limit: number, f: Filters = {}): Promise<Sponsored[]> {
  let q = supabase
    .from("ads")
    .select(`id, property:properties!inner(${PROPERTY_SELECT})`)
    .eq("placement", placement)
    .eq("ad_is_live", true)
    .eq("property.status", "published");
  if (f.ubicacion) {
    const like = `*${f.ubicacion}*`;
    q = q.or([`city.ilike.${like}`, `state.ilike.${like}`, `neighborhood.ilike.${like}`].join(","), { referencedTable: "property" });
  }
  if (f.tipo) q = q.eq("property.property_type", f.tipo);
  if (f.operacion) q = q.eq("property.operation", f.operacion);
  if (f.min !== undefined) q = q.gte("property.price", f.min);
  if (f.max !== undefined) q = q.lte("property.price", f.max);
  const { data, error } = await q.limit(50);
  if (error) return []; // un anuncio nunca debe tumbar el buscador ni el muro
  const rows = (data as unknown as { id: string; property: PropertyRow }[]) ?? [];
  const seen = new Set<string>();
  return shuffle(rows)
    .filter((r) => !seen.has(r.property.id) && seen.add(r.property.id))
    .slice(0, limit)
    .map((r) => ({ adId: r.id, property: toProperty(r.property) }));
}
