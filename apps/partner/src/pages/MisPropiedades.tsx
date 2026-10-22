import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import type { Property, PropertyStatus } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { ALL_STATUSES, STATUS_ACTION, STATUS_LABEL, formatPrice } from "../lib/properties";

/**
 * ZAI-21 · RF-VEN-01 · "Mis propiedades".
 * Lista solo las del vendedor (seller_id = usuario) en todos sus estados.
 * Las políticas RLS de ZAI-20 impiden ver o editar las de otro vendedor.
 */
export default function MisPropiedades() {
  const { session } = useAuth();
  const userId = session!.user.id;
  const [rows, setRows] = useState<Property[] | null>(null);
  const [error, setError] = useState<string | null>(null);

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
    load();
  }

  async function remove(p: Property) {
    if (!window.confirm(`¿Borrar "${p.data.title}"? No se puede deshacer.`)) return;
    const { error } = await supabase.from("properties").delete().eq("id", p.id);
    if (error) setError(error.message);
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
      {rows === null && <p>Cargando…</p>}
      {rows?.length === 0 && <p className="card">Todavía no tienes propiedades. Crea la primera.</p>}
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
