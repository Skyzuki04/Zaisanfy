import { useCallback, useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { PROPERTY_SELECT, toProperty, type Property, type PropertyRow, type PropertyStatus, friendlyError } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { withSession } from "../components/Layout";
import { ALL_STATUSES, STATUS_ACTION, STATUS_LABEL, formatPrice } from "../lib/properties";

type Quota = { plan_id: string; plan_name: string; max_published: number | null; published: number };

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";

export default function MisPropiedades() {
  const { session } = useAuth();
  const userId = session!.user.id;
  const [rows, setRows] = useState<Property[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const location = useLocation();
  const [quota, setQuota] = useState<Quota | null>(null);
  const [notice, setNotice] = useState<string | null>((location.state as { notice?: string } | null)?.notice ?? null);

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from("properties")
      .select(PROPERTY_SELECT)
      .eq("seller_id", userId)
      .order("updated_at", { ascending: false });
    if (error) setError(friendlyError(error));
    setRows(((data as unknown as PropertyRow[]) ?? []).map(toProperty));
    // Límite WIP del plan: cuántas puede tener publicadas a la vez (0013)
    const { data: q } = await supabase.rpc("my_publish_quota").maybeSingle();
    setQuota((q as Quota | null) ?? null);
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);

  async function changeStatus(id: string, status: PropertyStatus) {
    setError(null);
    const { error } = await supabase.from("properties").update({ status }).eq("id", id);
    if (error) setError(friendlyError(error));
    else setNotice(status === "published" ? "Publicada. Ya aparece en el Escaparate." : `Ahora está como “${STATUS_LABEL[status]}”.`);
    load();
  }

  async function remove(p: Property) {
    if (!window.confirm(`¿Borrar "${p.data.title}"? No se puede deshacer.`)) return;
    const { error } = await supabase.from("properties").delete().eq("id", p.id);
    if (error) setError(friendlyError(error));
    else setNotice(`Se borró “${p.data.title}”.`);
    load();
  }

  const atLimit = !!quota && quota.max_published !== null && quota.published >= quota.max_published;

  return (
    <section>
      <div className="row between">
        <h1>Mis propiedades</h1>
        <Link to="/propiedades/nueva" className="button primary">
          + Nueva propiedad
        </Link>
      </div>
      {quota && (
        <p className={`quota ${atLimit ? "full" : ""}`} role="status">
          Plan <strong>{quota.plan_name}</strong>:{" "}
          {quota.max_published === null ? (
            <>{quota.published} publicadas (sin límite)</>
          ) : (
            <>
              {quota.published} de {quota.max_published} publicadas
              {atLimit && <> · Llegaste al límite. Despublica una o <Link to="/plan">mejora tu plan</Link> para publicar más.</>}
            </>
          )}
        </p>
      )}
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
                    <button
                      key={s}
                      onClick={() => changeStatus(p.id, s)}
                      className="small"
                      title={s === "published" && atLimit ? "Llegaste al límite de publicaciones de tu plan" : undefined}
                    >
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
