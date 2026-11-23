// ZAI-32: portal de Stripe para cambiar la tarjeta o cancelar el plan.
// Al cancelar, Stripe lo deja activo hasta fin del periodo pagado y luego avisa al webhook → regresa a Freemium.
import { admin, asUser, consoleUrl, cors, json, stripe } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const { data: auth } = await asUser(req).auth.getUser();
  if (!auth?.user) return json({ error: "Inicia sesión" }, 401);

  const { data } = await admin().from("billing_customers").select("stripe_customer_id").eq("user_id", auth.user.id).maybeSingle();
  if (!data) return json({ error: "Todavía no tienes un plan de pago" }, 404);
  try {
    const portal = await stripe.billingPortal.sessions.create({ customer: data.stripe_customer_id, return_url: `${consoleUrl()}/plan`, locale: "es" });
    return json({ url: portal.url });
  } catch (e) {
    console.error("stripe-portal", e);
    return json({ error: "No se pudo abrir el portal de pagos" }, 500);
  }
});
