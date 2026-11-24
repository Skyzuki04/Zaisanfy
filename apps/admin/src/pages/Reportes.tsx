import { useCallback, useEffect, useState } from "react";
import { friendlyError } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";

// ZAI-33 (antitrolls): bandeja del admin con lo que reportaron los usuarios (migración 0018).
type Row = {
  target: "propiedad" | "publicacion";
  target_id: string;
  title: string | null;
  owner_name: string | null;
  reports: number;
  reasons: string;
  last_details: string | null;
  last_at: string;
  is_hidden: boolean;
};

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";
const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const REASON: Record<string, string> = {
  fraude: "Fraude",
  datos_falsos: "Datos falsos",
  contenido_inapropiado: "Inapropiado",
  spam: "Spam",
  otro: "Otro",
};

export default function Reportes() {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc("admin_reports");
    if (error) setError(friendlyError(error));
    setRows(((data as Row[]) ?? []).map((r) => ({ ...r, reports: Number(r.reports) })));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function resolve(r: Row, action: "ocultar" | "descartar") {
    if (action === "ocultar" && !window.confirm(`¿Ocultar “${r.title}”? Dejará de verse en el Escaparate.`)) return;
    setError(null);
    setBusy(r.target_id);
    const { error } = await supabase.rpc("resolve_report", { p_target: r.target, p_target_id: r.target_id, p_action: action });
    setBusy(null);
    if (error) return setError(friendlyError(error));
    setNotice(action === "ocultar" ? `Se ocultó “${r.title}”.` : `Se descartaron los reportes de “${r.title}”.`);
    load();
  }

  return (
    <section>
      <h1>Reportes</h1>
      <p className="muted">Propiedades y publicaciones que reportaron los usuarios. Ocúltalas si rompen las reglas o descarta el reporte.</p>
      {notice && <p className="flash" role="status">{notice}</p>}
      {error && <p className="error">{error}</p>}
      {rows === null && <p>Cargando…</p>}
      {rows?.length === 0 && (
        <div className="card empty-state">
          <h2>
            Sin reportes <em>pendientes</em>
          </h2>
        </div>
      )}
      {rows && rows.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Qué</th>
              <th>De</th>
              <th>Reportes</th>
              <th>Motivo</th>
              <th>Último</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.target_id}>
                <td>
                  <a href={`${visitorUrl}/${r.target === "propiedad" ? "propiedad" : "publicaciones"}/${r.target_id}`} target="_blank" rel="noreferrer">
                    {r.title ?? "—"}
                  </a>
                  <div className="muted small">{r.target === "propiedad" ? "Propiedad" : "Publicación"}{r.is_hidden && " · ya oculta"}</div>
                </td>
                <td>{r.owner_name ?? "—"}</td>
                <td>{r.reports}</td>
                <td>
                  {r.reasons.split(", ").map((x) => REASON[x] ?? x).join(", ")}
                  {r.last_details && <div className="muted small">“{r.last_details}”</div>}
                </td>
                <td className="small">{dateFmt.format(new Date(r.last_at))}</td>
                <td className="actions">
                  <button type="button" className="small danger" disabled={busy !== null} onClick={() => resolve(r, "ocultar")}>
                    Ocultar
                  </button>
                  <button type="button" className="small" disabled={busy !== null} onClick={() => resolve(r, "descartar")}>
                    Descartar
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
