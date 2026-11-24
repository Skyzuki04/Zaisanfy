import { useEffect, useState } from "react";
import { useLocation } from "react-router-dom";
import { friendlyError } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { mxn, openBillingPortal, paymentNotice, startCheckout } from "../lib/pay";

// ZAI-32 · RF-VEN-04: planes Freemium, Pro y Enterprise con Stripe.
type Plan = { id: string; name: string; price_mxn: number; max_published: number | null; monthly_credits: number; can_advertise: boolean };
type Sub = { plan_id: string; plan_name: string; status: string | null; current_period_end: string | null; cancel_at_period_end: boolean; credits: number };
type Move = { created_at: string; amount: number; reason: "plan" | "desbloqueo" | "ajuste"; request_id: string | null };

const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "long", year: "numeric" });
const REASON: Record<Move["reason"], string> = { plan: "Créditos de tu plan", desbloqueo: "Desbloqueaste un contacto", ajuste: "Ajuste" };

export default function MiPlan() {
  const { profile } = useAuth();
  const location = useLocation();
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [sub, setSub] = useState<Sub | null>(null);
  const [moves, setMoves] = useState<Move[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const notice = paymentNotice(location.search, "¡Pago recibido! Tu plan se actualiza en unos segundos.");

  useEffect(() => {
    let tries = 0;
    async function load() {
      const [p, s, m] = await Promise.all([
        supabase.from("plans").select("id, name, price_mxn, max_published, monthly_credits, can_advertise").order("sort_order"),
        supabase.rpc("my_subscription").maybeSingle(),
        supabase.rpc("my_credit_history"),
      ]);
      if (p.error || s.error) setError(friendlyError(p.error ?? s.error));
      setPlans((p.data as Plan[]) ?? []);
      setSub((s.data as Sub | null) ?? null);
      setMoves((m.data as Move[]) ?? []);
      // Al volver de Stripe el webhook tarda unos segundos: se recarga un par de veces
      if (notice && notice.startsWith("¡") && (s.data as Sub | null)?.plan_id === "freemium" && tries++ < 5) setTimeout(load, 2000);
    }
    load();
  }, [notice]);

  async function choose(planId: string) {
    setError(null);
    setBusy(planId);
    const err = await startCheckout({ kind: "plan", planId });
    setBusy(null);
    if (err) setError(err);
  }

  async function manage() {
    setError(null);
    setBusy("portal");
    const err = await openBillingPortal();
    setBusy(null);
    if (err) setError(err);
  }

  const isCreative = profile?.role === "creativo";
  const paid = sub && sub.plan_id !== "freemium";

  return (
    <section>
      <h1>Mi plan</h1>
      {notice && <p className="flash" role="status">{notice}</p>}
      {error && <p className="error">{error}</p>}

      {sub && (
        <div className="card plan-current">
          <p>
            Tienes el plan <strong>{sub.plan_name}</strong>
            {sub.current_period_end && (
              <>
                {" "}· {sub.cancel_at_period_end ? "termina" : "se renueva"} el {dateFmt.format(new Date(sub.current_period_end))}
              </>
            )}
            {sub.cancel_at_period_end && <> y después regresas a Freemium</>}.
          </p>
          <p>
            Créditos para desbloquear contactos: <strong>{sub.credits}</strong>
          </p>
          {paid && (
            <button type="button" onClick={manage} disabled={busy !== null}>
              {busy === "portal" ? "Abriendo…" : "Cambiar tarjeta o cancelar"}
            </button>
          )}
        </div>
      )}

      {plans === null && <p>Cargando…</p>}
      <div className="plans">
        {plans?.map((p) => {
          const current = sub?.plan_id === p.id;
          return (
            <article key={p.id} className={`card plan ${current ? "current" : ""}`}>
              <h2>
                {p.name} {p.id === "pro" && !current && <span className="badge draft">Recomendado</span>}
              </h2>
              <p className="price">
                {Number(p.price_mxn) === 0 ? "Gratis" : <>{mxn.format(Number(p.price_mxn))}<small> /mes</small></>}
              </p>
              <ul>
                {!isCreative && <li>{p.max_published === null ? "Propiedades publicadas sin límite" : `Hasta ${p.max_published} propiedades publicadas`}</li>}
                <li>{p.monthly_credits > 0 ? `${p.monthly_credits} créditos al mes para desbloquear contactos` : "Desbloqueas contactos pagando cada uno"}</li>
                {!isCreative && <li>{p.can_advertise ? "Puedes anunciar tus propiedades" : "Sin anuncios"}</li>}
              </ul>
              {current ? (
                <span className="badge published">Tu plan actual</span>
              ) : Number(p.price_mxn) > 0 ? (
                <button type="button" className="primary" onClick={() => choose(p.id)} disabled={busy !== null}>
                  {busy === p.id ? "Abriendo Stripe…" : paid ? `Cambiar a ${p.name}` : `Contratar ${p.name}`}
                </button>
              ) : (
                paid && <span className="muted small">Cancela tu plan para regresar a Freemium</span>
              )}
            </article>
          );
        })}
      </div>
      <p className="muted small">Pagos seguros con Stripe. En modo de prueba usa la tarjeta 4242 4242 4242 4242, cualquier fecha futura y cualquier CVC.</p>

      {moves.length > 0 && (
        <>
          <h2>Historial</h2>
          <table className="table">
            <thead>
              <tr>
                <th>Fecha</th>
                <th>Movimiento</th>
                <th>Créditos</th>
              </tr>
            </thead>
            <tbody>
              {moves.map((m, i) => (
                <tr key={i}>
                  <td>{dateFmt.format(new Date(m.created_at))}</td>
                  <td>{m.amount === 0 ? "Desbloqueaste un contacto (pagado con tarjeta)" : REASON[m.reason]}</td>
                  <td>{m.amount > 0 ? `+${m.amount}` : m.amount === 0 ? "—" : m.amount}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </section>
  );
}
