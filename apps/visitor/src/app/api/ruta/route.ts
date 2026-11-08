import { NextResponse, type NextRequest } from "next/server";
import { PROPERTY_SELECT, toProperty, type PropertyRow } from "@zaisanfy/schemas";
import { supabase } from "@/lib/supabase";
import { MAX_STOPS, planRoute, RouteError, type Point } from "@/lib/route-plan";

// RF-VIS-05: ruta optimizada por Mi Lista. La llave de Google se queda en el servidor.
type Body = { origin?: { lat?: unknown; lng?: unknown; address?: unknown }; propertyIds?: unknown };

const fail = (error: string, status = 400) => NextResponse.json({ error }, { status });
const isUuid = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v);

function parseOrigin(o: Body["origin"]): Point | null {
  if (!o) return null;
  const lat = Number(o.lat);
  const lng = Number(o.lng);
  if (o.lat !== undefined && Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) return { lat, lng };
  const address = typeof o.address === "string" ? o.address.trim().slice(0, 200) : "";
  return address.length >= 5 ? { address } : null;
}

export async function POST(req: NextRequest) {
  // Solo con sesión (Mi Lista es de cuentas): evita que cualquiera gaste la llave de Google
  const token = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth } = token ? await supabase.auth.getUser(token) : { data: { user: null } };
  if (!auth.user) return fail("Inicia sesión para planear tu ruta", 401);

  const body = (await req.json().catch(() => ({}))) as Body;
  const origin = parseOrigin(body.origin);
  if (!origin) return fail("Elige tu punto de salida: tu ubicación actual o una dirección.");
  const ids = Array.isArray(body.propertyIds) ? [...new Set(body.propertyIds.filter(isUuid))] : [];
  if (ids.length === 0) return fail("Elige al menos una propiedad de tu lista.");
  if (ids.length > MAX_STOPS) return fail(`Google Maps abre rutas de hasta ${MAX_STOPS} propiedades. Quita algunas.`);

  const { data, error } = await supabase.from("properties").select(PROPERTY_SELECT).in("id", ids).eq("status", "published");
  if (error) return fail("No pudimos leer tus propiedades. Intenta de nuevo.", 500);
  const properties = ((data as unknown as PropertyRow[]) ?? []).map(toProperty);
  if (properties.length === 0) return fail("Esas propiedades ya no están disponibles.");

  try {
    return NextResponse.json(await planRoute(origin, properties, process.env.GOOGLE_MAPS_API_KEY || undefined));
  } catch (e) {
    if (e instanceof RouteError) return fail(e.message, 422);
    console.error("ruta", e);
    return fail("No pudimos calcular la ruta. Intenta de nuevo en un momento.", 502);
  }
}
