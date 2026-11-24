// Piezas comunes de las funciones de Stripe (ZAI-32, ZAI-34, ZAI-36).
// Variables (Supabase → Edge Functions → Secrets): STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, CONSOLE_URL.
// SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY ya vienen puestas por Supabase.
import Stripe from "npm:stripe@17.7.0";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.49.4";

export const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2025-02-24.acacia",
  httpClient: Stripe.createFetchHttpClient(),
});

export const consoleUrl = () => (Deno.env.get("CONSOLE_URL") ?? "http://localhost:5173").replace(/\/$/, "");

// Cliente con permisos de servidor: solo vive aquí, nunca llega al navegador
export const admin = (): SupabaseClient =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

// Cliente "como el usuario": respeta RLS y auth.uid()
export const asUser = (req: Request): SupabaseClient =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

/** Cliente de Stripe del usuario; lo crea la primera vez. */
export async function customerFor(userId: string, email: string | undefined): Promise<string> {
  const db = admin();
  const { data } = await db.from("billing_customers").select("stripe_customer_id").eq("user_id", userId).maybeSingle();
  if (data?.stripe_customer_id) return data.stripe_customer_id;
  const customer = await stripe.customers.create({ email, metadata: { user_id: userId } });
  const { error } = await db.rpc("stripe_save_customer", { p_user: userId, p_customer: customer.id });
  if (error) throw error;
  // Si dos pestañas lo crearon al mismo tiempo, se queda el que entró primero
  const { data: saved } = await db.from("billing_customers").select("stripe_customer_id").eq("user_id", userId).single();
  return saved!.stripe_customer_id;
}

export const toMxn = (cents: number | null | undefined) => Math.round(cents ?? 0) / 100;
