import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { CONTACT_KIND_LABEL, CONTACT_STATUS_LABEL, ContactStatus, type ContactRequest } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";

type Row = ContactRequest & {
  property: { id: string; data: { title: string } } | null;
  post: { id: string; title: string } | null;
};

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";
const ORDER: Record<string, number> = { nueva: 0, contactado: 1, agendada: 2, cerrada: 3 };
const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const waLink = (phone: string) => `https://wa.me/${phone.replace(/\D/g, "").replace(/^(\d{10})$/, "52$1")}`;

export default function Solicitudes() {
  const { session, profile } = useAuth();
  const userId = session!.user.id;
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<"abiertas" | "todas">("abiertas");

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from("contact_requests")
      .select("*, property:properties(id, data), post:creative_posts(id, title)")
      .eq("recipient_id", userId)
      .order("created_at", { ascending: false });
    if (error) setError(error.message);
    const list = ((data as unknown as Row[]) ?? []).sort((a, b) => ORDER[a.status] - ORDER[b.status]);
    setRows(list);
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);

  async function changeStatus(id: string, status: ContactStatus) {
    setError(null);
    const { error } = await supabase.from("contact_requests").update({ status }).eq("id", id);
    if (error) return setError(error.message);
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
      {error && <p className="error">{error}</p>}
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
            <li key={r.id} className={`card request ${r.status}`}>
              <div className="row between">
                <span className="eyebrow">{CONTACT_KIND_LABEL[r.kind]}</span>
                <span className="muted small">{dateFmt.format(new Date(r.created_at))}</span>
              </div>
              <h2>
                {r.kind === "visita"
                  ? r.property
                    ? <Link to={`/propiedades/${r.property.id}`}>{r.property.data.title}</Link>
                    : "Propiedad borrada"
                  : r.post
                    ? <>Sobre: <a href={`${visitorUrl}/publicaciones/${r.post.id}`} target="_blank" rel="noreferrer">{r.post.title}</a></>
                    : "Desde tu perfil"}
              </h2>
              <dl className="request-data">
                <div><dt>Cliente</dt><dd>{r.requester_name ?? "—"}</dd></div>
                <div><dt>Correo</dt><dd>{r.requester_email ? <a href={`mailto:${r.requester_email}`}>{r.requester_email}</a> : "—"}</dd></div>
                {r.phone && <div><dt>Teléfono</dt><dd><a href={`tel:${r.phone}`}>{r.phone}</a></dd></div>}
                {r.operation && <div><dt>Para</dt><dd>{r.operation === "venta" ? "Comprar" : "Rentar"}</dd></div>}
                {r.preferred_times && <div><dt>Horario</dt><dd>{r.preferred_times}</dd></div>}
              </dl>
              {r.message && <p className="request-msg">“{r.message}”</p>}
              <div className="row between">
                <div className="row">
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
