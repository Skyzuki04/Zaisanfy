import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { supabase } from "../lib/supabase";

// Fila de my_ad_stats(): un anuncio con sus vistas y clics
type AdStats = {
  ad_id: string;
  property_id: string;
  property_title: string;
  placement: "buscador" | "muro";
  starts_on: string;
  ends_on: string;
  is_live: boolean;
  impressions: number;
  clicks: number;
};

const PLACEMENT_LABEL: Record<AdStats["placement"], string> = { buscador: "Buscador", muro: "Muro" };
const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
const fmtDate = (d: string) => dateFmt.format(new Date(`${d}T00:00:00Z`));
const num = new Intl.NumberFormat("es-MX");

function adState(a: AdStats) {
  if (a.is_live) return { label: "Activo", cls: "published" };
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "America/Mexico_City" });
  if (a.starts_on > today) return { label: "Programado", cls: "draft" };
  if (a.ends_on < today) return { label: "Terminado", cls: "closed" };
  return { label: "En pausa", cls: "hidden" }; // pago pendiente o propiedad no publicada
}

export default function MisAnuncios() {
  const [rows, setRows] = useState<AdStats[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    supabase.rpc("my_ad_stats").then(({ data, error }) => {
      if (error) setError(error.message);
      setRows(((data as AdStats[]) ?? []).map((r) => ({ ...r, impressions: Number(r.impressions), clicks: Number(r.clicks) })));
    });
  }, []);

  return (
    <section>
      <h1>Mis anuncios</h1>
      <p className="muted">Tus propiedades patrocinadas en el buscador y el muro: cuántas veces se mostraron y cuántos clics recibieron.</p>
      {error && <p className="error">{error}</p>}
      {rows === null && <p>Cargando…</p>}
      {rows?.length === 0 && (
        <div className="card empty-state">
          <h2>
            Todavía no tienes <em>anuncios</em>
          </h2>
          <p className="muted">Cuando anuncies una propiedad, aquí verás cuántas veces se mostró y cuántos clics recibió.</p>
          <Link to="/propiedades" className="button primary">
            Ver mis propiedades
          </Link>
        </div>
      )}
      {rows && rows.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Propiedad</th>
              <th>Dónde</th>
              <th>Fechas pagadas</th>
              <th>Estado</th>
              <th>Veces mostrado</th>
              <th>Clics</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((a) => {
              const st = adState(a);
              return (
                <tr key={a.ad_id}>
                  <td>
                    <Link to={`/propiedades/${a.property_id}`}>{a.property_title}</Link>
                  </td>
                  <td>{PLACEMENT_LABEL[a.placement]}</td>
                  <td>
                    {fmtDate(a.starts_on)} – {fmtDate(a.ends_on)}
                  </td>
                  <td>
                    <span className={`badge ${st.cls}`}>{st.label}</span>
                  </td>
                  <td>{num.format(a.impressions)}</td>
                  <td>
                    {num.format(a.clicks)}
                    {a.impressions > 0 && <span className="muted small"> ({((a.clicks / a.impressions) * 100).toFixed(1)}%)</span>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </section>
  );
}
