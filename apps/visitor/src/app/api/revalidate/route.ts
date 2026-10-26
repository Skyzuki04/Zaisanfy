import { revalidatePath } from "next/cache";
import { NextResponse, type NextRequest } from "next/server";

/**
 * ZAI-26 · RNF-OPS-01 · ISR on-demand.
 * Supabase (Database Webhook en la tabla properties) llama aquí cuando una propiedad cambia,
 * por ejemplo el precio, y la página se regenera al momento en lugar de esperar la hora.
 * Protegido con el encabezado x-revalidate-secret = REVALIDATE_SECRET (solo en el servidor).
 */
type WebhookBody = {
  type?: "INSERT" | "UPDATE" | "DELETE";
  table?: string;
  record?: { id?: string } | null;
  old_record?: { id?: string } | null;
};

export async function POST(req: NextRequest) {
  const secret = process.env.REVALIDATE_SECRET;
  if (!secret || req.headers.get("x-revalidate-secret") !== secret) {
    return NextResponse.json({ ok: false, error: "No autorizado" }, { status: 401 });
  }
  const body = (await req.json().catch(() => ({}))) as WebhookBody;
  const id = body.record?.id ?? body.old_record?.id;
  if (!id) return NextResponse.json({ ok: false, error: "Falta el id de la propiedad" }, { status: 400 });

  const paths = [`/propiedad/${id}`, "/", "/sitemap.xml"];
  for (const path of paths) revalidatePath(path);
  return NextResponse.json({ ok: true, revalidated: paths });
}
