import { useCallback, useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { CONTACT_KIND_LABEL, CONTACT_STATUS_LABEL, ContactStatus, type InboxRow, friendlyError } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { mxn, paymentNotice, startCheckout } from "../lib/pay";

// locked: cotización con el contacto oculto hasta desbloquearla (ZAI-33/34, migración 0015)
type Row = InboxRow & { locked?: boolean; unlocked_at?: string | null };

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";
const ORDER: Record<string, number> = { nueva: 0, contactado: 1, agendada: 2, cerrada: 3 };
const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const waLink = (phone: string) => `https://wa.me/${phone.replace(/\D/g, "").replace(/^(\d{10})$/, "52$1")}`;

export default function Solicitudes() {
  const { profile } = useAuth();
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<"abiertas" | "todas">("abiertas");
  const [busy, setBusy] = useState<string | null>(null);
  const [credits, setCredits] = useState<number>(0);
  const [leadPrice, setLeadPrice] = useState<number>(49);
  const location = useLocation();
  const [notice, setNotice] = useState<string | null>(paymentNotice(location.search, "¡Pago recibido! El contacto se desbloquea en unos segundos."));

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc("my_inbox");
    if (error) setError(friendlyError(error));
    const list = ((data as unknown as Row[]) ?? []).sort((a, b) => ORDER[a.status] - ORDER[b.status]);
    setRows(list);
    const [c, p] = await Promise.all([supabase.rpc("my_credits"), supabase.rpc("lead_price_mxn")]);
    setCredits(Number(c.data ?? 0));
    if (p.data) setLeadPrice(Number(p.data));
    return list;
  }, []);

  useEffect(() => {
    // Al volver de Stripe el webhook tarda unos segundos en desbloquear: se recarga un par de veces
    if (!new URLSearchParams(location.search).has("pago")) return;
    let tries = 0;
    const id = setInterval(async () => {
      const list = await load();
      if (++tries >= 5 || !list.some((r) => r.locked)) clearInterval(id);
    }, 2000);
    return () => clearInterval(id);
  }, [load, location.search]);

  async function unlockWithCredit(id: string) {
    setError(null);
    setNotice(null);
    setBusy(id);
    const { data, error } = await supabase.rpc("unlock_lead_with_credit", { p_request: id });
    setBusy(null);
    if (error) return setError(friendlyError(error));
    setNotice(data === "ya_desbloqueada" ? "Ese contacto ya estaba desbloqueado. No se te cobró de nuevo." : "Contacto desbloqueado con 1 crédito.");
    load();
  }

  async function unlockWithCard(id: string) {
    setError(null);
    setBusy(id);
    const err = await startCheckout({ kind: "lead", requestId: id });
    setBusy(null);
    if (err) setError(err);
  }

  useEffect(() => {
    load();
  }, [load]);

  async function changeStatus(id: string, status: ContactStatus) {
    setError(null);
    const { error } = await supabase.from("contact_requests").update({ status }).eq("id", id);
    if (error) return setError(friendlyError(error));
    setRows((rs) => rs && rs.map((r) => (r.id === id ? { ...r, status } : r)).sort((a, b) => ORDER[a.status] - ORDER[b.status]));
  }

  const nuevas = rows?.filter((r) => r.status === "nueva").length ?? 0;
  const visible = rows?.filter((r) => filter === "todas" || r.status !== "cerrada") ?? [];
  const isCreative = profile?.role === "creativo";

  return (
    <section>
      <div className="row between">
        <div>
          <h1>
            Solicitudes{nuevas > 0 && <span className="count-badge">{nuevas} nuevas</span>}
          </h1>
          <p className="muted">
            {isCreative ? "Clientes que pidieron una cotización." : "Clientes que quieren visitar tus propiedades."} Contáctalos y actualiza el estado.
          </p>
        </div>
        <div className="tabs">
          <button className={filter === "abiertas" ? "active" : ""} onClick={() => setFilter("abiertas")} type="button">
            Abiertas
          </button>
          <button className={filter === "todas" ? "active" : ""} onClick={() => setFilter("todas")} type="button">
            Todas
          </button>
        </div>
      </div>
      {notice && <p className="flash" role="status">{notice}</p>}
      {error && <p className="error">{error}</p>}
      {isCreative && rows?.some((r) => r.locked) && (
        <p className="muted">
          Los datos de contacto de las cotizaciones están ocultos hasta que las desbloquees. Tienes <strong>{credits}</strong> créditos
          {credits === 0 && <> · <Link to="/plan">consigue créditos con un plan</Link></>}.
        </p>
      )}
      {rows === null && <p>Cargando…</p>}
      {rows && visible.length === 0 && (
        <div className="card empty-state">
          <h2>
            {rows.length === 0 ? "Todavía no tienes " : "No hay solicitudes "}
            <em>{rows.length === 0 ? "solicitudes" : "abiertas"}</em>
          </h2>
          <p className="muted">
            {isCreative
              ? "Cuando alguien pida una cotización desde tu perfil o tus publicaciones, aparecerá aquí."
              : "Cuando un cliente pida visitar una de tus propiedades publicadas, aparecerá aquí."}
          </p>
          <Link to={isCreative ? "/portafolio/nueva" : "/propiedades"} className="button primary">
            {isCreative ? "+ Subir más trabajos" : "Ver mis propiedades"}
          </Link>
        </div>
      )}
      {visible.length > 0 && (
        <ul className="requests">
          {visible.map((r) => (
            <li key={r.id} className={`card request ${r.status} ${r.locked ? "locked" : ""}`}>
              <div className="row between">
                <span className="eyebrow">{CONTACT_KIND_LABEL[r.kind]}</span>
                <span className="muted small">{dateFmt.format(new Date(r.created_at))}</span>
              </div>
              <h2>
                {r.kind === "visita"
                  ? r.property_id
                    ? <Link to={`/propiedades/${r.property_id}`}>{r.property_title}</Link>
                    : "Propiedad borrada"
                  : r.post_id
                    ? <>Sobre: <a href={`${visitorUrl}/publicaciones/${r.post_id}`} target="_blank" rel="noreferrer">{r.post_title}</a></>
                    : "Desde tu perfil"}
              </h2>
              {r.locked && <span className="badge hidden lock-badge">🔒 Contacto bloqueado</span>}
              {r.unlocked_at && <span className="badge published lock-badge">Desbloqueado</span>}
              <dl className={`request-data ${r.locked ? "blurred" : ""}`}>
                <div><dt>Cliente</dt><dd>{r.requester_name ?? "—"}</dd></div>
                <div><dt>Correo</dt><dd>{r.locked ? "••••••@••••.com" : r.requester_email ? <a href={`mailto:${r.requester_email}`}>{r.requester_email}</a> : "—"}</dd></div>
                {r.locked && <div><dt>Teléfono</dt><dd>•• •••• ••••</dd></div>}
                {r.phone && <div><dt>Teléfono</dt><dd><a href={`tel:${r.phone}`}>{r.phone}</a></dd></div>}
                {r.operation && <div><dt>Para</dt><dd>{r.operation === "venta" ? "Comprar" : "Rentar"}</dd></div>}
                {r.preferred_times && <div><dt>Horario</dt><dd>{r.preferred_times}</dd></div>}
              </dl>
              {r.message && <p className="request-msg">“{r.message}”</p>}
              <div className="row between">
                <div className="row">
                  {r.locked && (
                    <>
                      <button type="button" className="small primary" disabled={busy !== null || credits < 1} onClick={() => unlockWithCredit(r.id)}>
                        {busy === r.id ? "Desbloqueando…" : "Desbloquear con 1 crédito"}
                      </button>
                      <button type="button" className="small" disabled={busy !== null} onClick={() => unlockWithCard(r.id)}>
                        Pagar {mxn.format(leadPrice)}
                      </button>
                    </>
                  )}
                  {r.phone && (
                    <a className="button small primary" href={waLink(r.phone)} target="_blank" rel="noreferrer">
                      WhatsApp
                    </a>
                  )}
                  {r.requester_email && (
                    <a className="button small" href={`mailto:${r.requester_email}?subject=${encodeURIComponent("Tu solicitud en Zaisanfy")}`}>
                      Responder por correo
                    </a>
                  )}
                </div>
                <label className="status-select">
                  Estado
                  <select value={r.status} onChange={(e) => changeStatus(r.id, e.target.value as ContactStatus)}>
                    {ContactStatus.options.map((s) => (
                      <option key={s} value={s}>
                        {CONTACT_STATUS_LABEL[s]}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
