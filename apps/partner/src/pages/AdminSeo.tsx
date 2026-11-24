import { useEffect, useState } from "react";
import { friendlyError } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";

// RF-ADM-02: SEO/GEO Score de 0 a 100 por propiedad y publicación, con qué le falta (migración 0021).
type Row = { kind: "propiedad" | "publicacion"; id: string; title: string; owner_name: string | null; status: string; score: number; tips: string[] };

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";

function color(score: number) {
  if (score >= 80) return "var(--ok, #2e7d4f)";
  if (score >= 50) return "#b7791f";
  return "var(--danger, #b42318)";
}

export default function AdminSeo() {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [kind, setKind] = useState<Row["kind"]>("propiedad");

  useEffect(() => {
    supabase.rpc("admin_seo_scores").then(({ data, error }) => {
      if (error) setError(friendlyError(error));
      setRows((data as Row[]) ?? []);
    });
  }, []);

  const list = rows?.filter((r) => r.kind === kind) ?? [];
  const avg = list.length ? Math.round(list.reduce((s, r) => s + r.score, 0) / list.length) : 0;

  return (
    <section>
      <h1>SEO/GEO Score</h1>
      <p className="muted">
        Qué tan bien sale cada ficha en Google y en buscadores con IA. Se califica de 0 a 100: título, descripción, fotos, 360°, ubicación y datos
        estructurados (JSON-LD). Las más bajas van primero.
      </p>
      <div className="tabs">
        <button type="button" className={kind === "propiedad" ? "active" : ""} onClick={() => setKind("propiedad")}>Propiedades</button>
        <button type="button" className={kind === "publicacion" ? "active" : ""} onClick={() => setKind("publicacion")}>Publicaciones</button>
      </div>
      {error && <p className="error">{error}</p>}
      {rows === null && !error && <p>Cargando…</p>}
      {rows && list.length === 0 && <p className="muted">Todavía no hay {kind === "propiedad" ? "propiedades publicadas" : "publicaciones"}.</p>}
      {list.length > 0 && (
        <>
          <p>
            Promedio: <strong style={{ color: color(avg) }}>{avg}</strong> / 100 · {list.length} {kind === "propiedad" ? "propiedades" : "publicaciones"}
          </p>
          <table className="table">
            <thead>
              <tr>
                <th>Ficha</th>
                <th>Score</th>
                <th>Qué le falta</th>
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id}>
                  <td>
                    <a href={`${visitorUrl}/${r.kind === "propiedad" ? "propiedad" : "publicaciones"}/${r.id}`} target="_blank" rel="noreferrer">{r.title}</a>
                    <div className="muted small">{r.owner_name ?? "—"}{r.status === "hidden" && " · oculta"}</div>
                  </td>
                  <td>
                    <strong style={{ color: color(r.score) }}>{r.score}</strong>
                    <div style={{ height: 6, width: 90, background: "#eee", borderRadius: 3, marginTop: 4 }} aria-hidden>
                      <div style={{ height: 6, width: `${r.score}%`, background: color(r.score), borderRadius: 3 }} />
                    </div>
                  </td>
                  <td className="small">{r.tips.length ? r.tips.join(" · ") : "Completa"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </section>
  );
}
