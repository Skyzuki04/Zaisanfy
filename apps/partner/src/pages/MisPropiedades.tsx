import { useCallback, useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import type { Property, PropertyStatus } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { withSession } from "../components/Layout";
import { ALL_STATUSES, STATUS_ACTION, STATUS_LABEL, formatPrice } from "../lib/properties";

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";

export default function MisPropiedades() {
  const { session } = useAuth();
  const userId = session!.user.id;
  const [rows, setRows] = useState<Property[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const location = useLocation();
  const [notice, setNotice] = useState<string | null>((location.state as { notice?: string } | null)?.notice ?? null);

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from("properties")
      .select("*")
      .eq("seller_id", userId)
      .order("updated_at", { ascending: false });
    if (error) setError(error.message);
    setRows((data as Property[]) ?? []);
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);

  async function changeStatus(id: string, status: PropertyStatus) {
    const { error } = await supabase.from("properties").update({ status }).eq("id", id);
    if (error) setError(error.message);
    else setNotice(status === "published" ? "Publicada. Ya aparece en el Escaparate." : `Ahora está como “${STATUS_LABEL[status]}”.`);
    load();
  }

  async function remove(p: Property) {
    if (!window.confirm(`¿Borrar "${p.data.title}"? No se puede deshacer.`)) return;
    const { error } = await supabase.from("properties").delete().eq("id", p.id);
    if (error) setError(error.message);
    else setNotice(`Se borró “${p.data.title}”.`);
    load();
  }

  return (
    <section>
      <div className="row between">
        <h1>Mis propiedades</h1>
        <Link to="/propiedades/nueva" className="button primary">
          + Nueva propiedad
        </Link>
      </div>
      {error && <p className="error">{error}</p>}
      {notice && (
        <p className="flash" role="status">
          {notice}
          <button type="button" className="link" onClick={() => setNotice(null)} aria-label="Cerrar aviso">
            ✕
          </button>
        </p>
      )}
      {rows === null && <p>Cargando…</p>}
      {rows?.length === 0 && (
        <div className="card empty-state">
          <h2>
            Todavía no tienes <em>propiedades</em>
          </h2>
          <p className="muted">Crea tu primera propiedad, súbele fotos y su recorrido 360°, y publícala para que aparezca en el Escaparate.</p>
          <Link to="/propiedades/nueva" className="button primary">
            + Crear mi primera propiedad
          </Link>
        </div>
      )}
      {rows && rows.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Propiedad</th>
              <th>Ciudad</th>
              <th>Precio</th>
              <th>Estado</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => (
              <tr key={p.id}>
                <td>
                  <Link to={`/propiedades/${p.id}`}>{p.data.title}</Link>
                </td>
                <td>{p.data.location.city}</td>
                <td>{formatPrice(p.data)}</td>
                <td>
                  <span className={`badge ${p.status}`}>{STATUS_LABEL[p.status]}</span>
                </td>
                <td className="actions">
                  <Link to={`/propiedades/${p.id}`} className="button small">
                    Editar
                  </Link>
                  {p.status === "published" && (
                    <a href={`${visitorUrl}/propiedad/${p.id}`} target="_blank" rel="noreferrer" onClick={(e) => withSession(e, session)} className="button small">
                      Ver publicada ↗
                    </a>
                  )}
                  {ALL_STATUSES.filter((s) => s !== p.status).map((s) => (
                    <button key={s} onClick={() => changeStatus(p.id, s)} className="small">
                      {STATUS_ACTION[s]}
                    </button>
                  ))}
                  <button onClick={() => remove(p)} className="small danger">
                    Borrar
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
