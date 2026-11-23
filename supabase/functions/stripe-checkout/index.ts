// ZAI-32 / ZAI-34 / ZAI-36: abre Stripe Checkout para
//   { kind: "plan", planId: "pro" | "enterprise" }                       → suscripción mensual
//   { kind: "lead", requestId }                                          → desbloquear un lead (pago único)
//   { kind: "ad", propertyId, placement: "buscador" | "muro", startsOn, endsOn } → anuncio (pago único)
// Responde { url } y la Consola redirige ahí. Lo que se cobra lo decide la base, nunca el navegador.
import { admin, asUser, consoleUrl, cors, customerFor, json, stripe } from "../_shared/stripe.ts";

const isUuid = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f-]{36}$/i.test(v);
const isDate = (v: unknown): v is string => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  const db = asUser(req);
  const { data: auth } = await db.auth.getUser();
  const user = auth?.user;
  if (!user) return json({ error: "Inicia sesión para pagar" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Solicitud inválida" }, 400);
  }

  try {
    const customer = await customerFor(user.id, user.email);
    const base = consoleUrl();

    if (body.kind === "plan") {
      const { data: plan } = await admin().from("plans").select("id, name, price_mxn, stripe_price_id").eq("id", body.planId).maybeSingle();
      if (!plan || Number(plan.price_mxn) <= 0) return json({ error: "Ese plan no existe o es gratis" }, 400);
      const { data: current } = await db.rpc("my_plan");
      if (current === plan.id) return json({ error: `Ya tienes el plan ${plan.name}` }, 409);

      const session = await stripe.checkout.sessions.create({
        mode: "subscription",
        customer,
        line_items: [
          plan.stripe_price_id
            ? { price: plan.stripe_price_id, quantity: 1 }
            : {
                quantity: 1,
                price_data: {
                  currency: "mxn",
                  unit_amount: Math.round(Number(plan.price_mxn) * 100),
                  recurring: { interval: "month" },
                  product_data: { name: `Zaisanfy ${plan.name}` },
                },
              },
        ],
        subscription_data: { metadata: { user_id: user.id, plan_id: plan.id } },
        metadata: { kind: "plan", user_id: user.id, plan_id: plan.id },
        success_url: `${base}/plan?pago=ok`,
        cancel_url: `${base}/plan?pago=cancelado`,
        locale: "es",
      });
      return json({ url: session.url });
    }

    if (body.kind === "lead") {
      if (!isUuid(body.requestId)) return json({ error: "Solicitud inválida" }, 400);
      const { data: inbox } = await db.rpc("my_inbox");
      const lead = (inbox as { id: string; locked: boolean }[] | null)?.find((r) => r.id === body.requestId);
      if (!lead) return json({ error: "No encontramos esta solicitud o no es tuya" }, 404);
      if (!lead.locked) return json({ error: "Esta solicitud ya está desbloqueada" }, 409);
      const { data: price } = await db.rpc("lead_price_mxn");

      const session = await stripe.checkout.sessions.create({
        mode: "payment",
        customer,
        line_items: [{ quantity: 1, price_data: { currency: "mxn", unit_amount: Math.round(Number(price) * 100), product_data: { name: "Desbloquear contacto (Zaisanfy)" } } }],
        metadata: { kind: "lead", user_id: user.id, request_id: body.requestId },
        success_url: `${base}/solicitudes?pago=ok`,
        cancel_url: `${base}/solicitudes?pago=cancelado`,
        locale: "es",
      });
      return json({ url: session.url });
    }

    if (body.kind === "ad") {
      const { propertyId, placement, startsOn, endsOn } = body;
      if (!isUuid(propertyId) || (placement !== "buscador" && placement !== "muro") || !isDate(startsOn) || !isDate(endsOn)) {
        return json({ error: "Revisa la propiedad, el lugar y las fechas" }, 400);
      }
      // ad_quote valida dueño, propiedad publicada, plan con anuncios y fechas, y regresa el precio
      const { data: amount, error } = await db.rpc("ad_quote", { p_property: propertyId, p_starts: startsOn, p_ends: endsOn });
      if (error) return json({ error: error.message, code: error.code }, 400);

      const session = await stripe.checkout.sessions.create({
        mode: "payment",
        customer,
        line_items: [{
          quantity: 1,
          price_data: {
            currency: "mxn",
            unit_amount: Math.round(Number(amount) * 100),
            product_data: { name: `Anuncio en el ${placement} del ${startsOn} al ${endsOn}` },
          },
        }],
        metadata: { kind: "ad", user_id: user.id, property_id: propertyId, placement, starts_on: startsOn, ends_on: endsOn },
        success_url: `${base}/anuncios?pago=ok`,
        cancel_url: `${base}/anuncios?pago=cancelado`,
        locale: "es",
      });
      return json({ url: session.url });
    }

    return json({ error: "No sé qué cobrar" }, 400);
  } catch (e) {
    console.error("stripe-checkout", e);
    return json({ error: "No se pudo abrir el pago. Intenta de nuevo." }, 500);
  }
});
