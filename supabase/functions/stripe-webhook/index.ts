// Webhook de Stripe: lo único que cambia planes, pagos, leads desbloqueados y anuncios.
// Se configura en Stripe → Developers → Webhooks con la URL de esta función y estos eventos:
//   checkout.session.completed, customer.subscription.created, customer.subscription.updated,
//   customer.subscription.deleted, invoice.paid
// Va sin verificación de JWT (supabase/config.toml): la seguridad es la firma de Stripe.
import type Stripe from "npm:stripe@17.7.0";
import { admin, stripe, toMxn } from "../_shared/stripe.ts";

const STATUS: Record<string, string> = {
  active: "activa",
  trialing: "en_prueba",
  past_due: "pago_vencido",
  unpaid: "pago_vencido",
  canceled: "cancelada",
  incomplete: "incompleta",
  incomplete_expired: "cancelada",
  paused: "cancelada",
};

const iso = (s: number | null | undefined) => (s ? new Date(s * 1000).toISOString() : null);

async function applySubscription(subId: string) {
  // Siempre se lee la versión actual en Stripe: los eventos pueden llegar desordenados o repetidos
  const sub = await stripe.subscriptions.retrieve(subId);
  const userId = sub.metadata.user_id;
  const planId = sub.metadata.plan_id;
  if (!userId || !planId) throw new Error(`Suscripción ${sub.id} sin user_id/plan_id en metadata`);
  const db = admin();

  // Cambio de plan (Pro → Enterprise o al revés): la suscripción vieja se cancela en Stripe
  // para que no se cobren las dos. Stripe luego avisa con customer.subscription.deleted.
  if (sub.status === "active" || sub.status === "trialing") {
    const { data: old } = await db
      .from("subscriptions")
      .select("stripe_subscription_id")
      .eq("user_id", userId)
      .in("status", ["activa", "en_prueba", "pago_vencido"])
      .neq("stripe_subscription_id", sub.id);
    for (const o of old ?? []) {
      if (o.stripe_subscription_id) await stripe.subscriptions.cancel(o.stripe_subscription_id, { prorate: true }).catch((e) => console.error("cancelar vieja", e));
    }
  }

  const { error } = await db.rpc("stripe_apply_subscription", {
    p_user: userId,
    p_plan: planId,
    p_stripe_subscription: sub.id,
    p_status: STATUS[sub.status] ?? "incompleta",
    p_period_start: iso(sub.current_period_start),
    p_period_end: iso(sub.current_period_end),
    p_cancel_at_period_end: sub.cancel_at_period_end,
  });
  if (error) throw error;
}

async function handle(event: Stripe.Event) {
  const db = admin();
  switch (event.type) {
    case "customer.subscription.created":
    case "customer.subscription.updated":
    case "customer.subscription.deleted":
      return applySubscription(event.data.object.id);

    case "invoice.paid": {
      const invoice = event.data.object;
      const subId = typeof invoice.subscription === "string" ? invoice.subscription : invoice.subscription?.id;
      if (!subId) return;
      // invoice.paid puede llegar antes que subscription.created: primero se asegura la suscripción
      await applySubscription(subId);
      const { error } = await db.rpc("stripe_record_invoice", {
        p_stripe_subscription: subId,
        p_amount_mxn: toMxn(invoice.amount_paid),
        p_payment_ref: invoice.id,
      });
      if (error) throw error;
      return;
    }

    case "checkout.session.completed": {
      const s = event.data.object;
      if (s.mode !== "payment" || s.payment_status !== "paid") return; // las suscripciones llegan por los otros eventos
      const m = s.metadata ?? {};
      const ref = typeof s.payment_intent === "string" ? s.payment_intent : s.id;
      if (m.kind === "lead") {
        const { error } = await db.rpc("stripe_unlock_lead", {
          p_user: m.user_id, p_request: m.request_id, p_amount_mxn: toMxn(s.amount_total), p_payment_ref: ref,
        });
        if (error) throw error;
      } else if (m.kind === "ad") {
        const { error } = await db.rpc("stripe_create_ad", {
          p_user: m.user_id, p_property: m.property_id, p_placement: m.placement,
          p_starts: m.starts_on, p_ends: m.ends_on, p_amount_mxn: toMxn(s.amount_total), p_payment_ref: ref,
        });
        if (error) throw error;
      }
      return;
    }
  }
}

Deno.serve(async (req) => {
  const signature = req.headers.get("Stripe-Signature");
  if (!signature) return new Response("Falta la firma", { status: 400 });
  const raw = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(raw, signature, Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "");
  } catch (e) {
    console.error("Firma inválida", e);
    return new Response("Firma inválida", { status: 400 });
  }

  try {
    await handle(event);
    return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    // 500 hace que Stripe reintente más tarde; las funciones de la base no duplican nada
    console.error(event.type, event.id, e);
    return new Response("Error al procesar", { status: 500 });
  }
});
