// RF-ADM-01 "impersonate": el admin entra a la cuenta de un usuario (vendedor, creativo o visitante).
// 1) La base revisa el permiso y deja bitácora: admin_start_impersonation() (migración 0022).
// 2) Aquí, con permisos de servidor, se genera un enlace de acceso de un solo uso. No se manda correo.
// Variables: CONSOLE_URL y VISITOR_URL (Edge Functions → Secrets). Las de Supabase ya vienen puestas.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const url = (name: string, fallback: string) => (Deno.env.get(name) ?? fallback).replace(/\/$/, "");
const isUuid = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  const body = (await req.json().catch(() => ({}))) as { userId?: unknown; reason?: unknown };
  if (!isUuid(body.userId)) return json({ error: "Falta el usuario" }, 400);
  const reason = typeof body.reason === "string" ? body.reason.slice(0, 200) : null;

  // Como el admin que la llama: la base decide si puede y lo registra
  const asAdmin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: target, error } = await asAdmin.rpc("admin_start_impersonation", { p_user: body.userId, p_reason: reason }).single();
  if (error || !target) {
    const status = error?.code === "42501" ? 403 : error?.code === "P0002" ? 404 : 400;
    return json({ error: error?.message ?? "No se pudo" }, status);
  }
  const { email, role } = target as { email: string; role: string };

  // A la app que usa ese usuario; ?como_admin=1 hace que la Consola muestre el aviso de modo admin
  const redirectTo = role === "visitante" ? `${url("VISITOR_URL", "http://localhost:3000")}/` : `${url("CONSOLE_URL", "http://localhost:5173")}/?como_admin=1`;

  const server = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error: linkError } = await server.auth.admin.generateLink({ type: "magiclink", email, options: { redirectTo } });
  if (linkError || !data?.properties?.action_link) {
    console.error("admin-impersonate", linkError);
    return json({ error: "No se pudo generar el acceso" }, 500);
  }
  return json({ url: data.properties.action_link, email, role });
});
