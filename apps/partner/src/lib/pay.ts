import { FunctionsHttpError } from "@supabase/supabase-js";
import { friendlyError } from "@zaisanfy/schemas";
import { supabase } from "./supabase";

// Abre Stripe (Edge Functions stripe-checkout y stripe-portal) y manda al usuario allá.
// Regresa un mensaje de error si algo falla; si todo sale bien, la página se va a Stripe.
export type CheckoutBody =
  | { kind: "plan"; planId: string }
  | { kind: "lead"; requestId: string }
  | { kind: "ad"; propertyId: string; placement: "buscador" | "muro"; startsOn: string; endsOn: string };

async function go(fn: "stripe-checkout" | "stripe-portal", body?: object): Promise<string | null> {
  const { data, error } = await supabase.functions.invoke<{ url?: string }>(fn, { body: body ?? {} });
  if (error) {
    if (error instanceof FunctionsHttpError) {
      const payload = (await error.context.json().catch(() => null)) as { error?: string; code?: string } | null;
      if (payload?.error) return payload.code ? friendlyError({ code: payload.code, message: payload.error }) : payload.error;
    }
    return "No se pudo abrir el pago. Revisa tu conexión e intenta de nuevo.";
  }
  if (!data?.url) return "No se pudo abrir el pago. Intenta de nuevo.";
  window.location.assign(data.url);
  return null;
}

export const startCheckout = (body: CheckoutBody) => go("stripe-checkout", body);
export const openBillingPortal = () => go("stripe-portal");

export const mxn = new Intl.NumberFormat("es-MX", { style: "currency", currency: "MXN", maximumFractionDigits: 0 });

/** Aviso al volver de Stripe (?pago=ok | cancelado). */
export function paymentNotice(search: string, ok: string): string | null {
  const p = new URLSearchParams(search).get("pago");
  if (p === "ok") return ok;
  if (p === "cancelado") return "Cancelaste el pago. No se te cobró nada.";
  return null;
}
