import { useCallback, useEffect, useState } from "react";
import { friendlyError } from "@zaisanfy/schemas";
import type { UserRole } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";

// RF-ADM-01: el admin gestiona, suspende y "ve como" (solo lectura) a cualquier usuario (migración 0021).
type User = {
  id: string;
  email: string;
  full_name: string | null;
  role: UserRole;
  plan: string;
  created_at: string;
  last_sign_in_at: string | null;
  email_confirmed: boolean;
  suspended: boolean;
  suspended_reason: string | null;
  properties: number;
  posts: number;
};

type Detail = {
  plan: string;
  credits: number;
  paid_mxn: number;
  properties: { id: string; title: string; status: string; city: string; price: number }[];
  posts: { id: string; title: string; hidden: boolean }[];
  requests_sent: number;
  requests_received: number;
  reports_against: number;
};

const ROLES: UserRole[] = ["visitante", "vendedor", "creativo", "admin"];
const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", year: "numeric" });
const mxn = new Intl.NumberFormat("es-MX", { style: "currency", currency: "MXN", maximumFractionDigits: 0 });

export default function AdminUsuarios() {
  const [search, setSearch] = useState("");
  const [users, setUsers] = useState<User[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [viewing, setViewing] = useState<{ user: User; detail: Detail } | null>(null);

  const load = useCallback(async (q: string) => {
    const { data, error } = await supabase.rpc("admin_users", { p_search: q || null });
    if (error) return setError(friendlyError(error));
    setUsers(((data as User[]) ?? []).map((u) => ({ ...u, properties: Number(u.properties), posts: Number(u.posts) })));
  }, []);

  useEffect(() => {
    const t = setTimeout(() => load(search.trim()), 250);
    return () => clearTimeout(t);
  }, [search, load]);

  async function run(u: User, fn: () => PromiseLike<{ error: unknown }>, done: string) {
    setError(null);
    setNotice(null);
    setBusy(u.id);
    const { error } = await fn();
    setBusy(null);
    if (error) return setError(friendlyError(error as never));
    setNotice(done);
    load(search.trim());
  }

  function toggleSuspend(u: User) {
    if (u.suspended) {
      return run(u, () => supabase.rpc("admin_set_suspended", { p_user: u.id, p_suspend: false }), `${u.email} ya puede usar su cuenta de nuevo.`);
    }
    const reason = window.prompt(`¿Por qué suspendes a ${u.email}? Su contenido dejará de verse y no podrá hacer cambios.`);
    if (reason === null) return;
    return run(u, () => supabase.rpc("admin_set_suspended", { p_user: u.id, p_suspend: true, p_reason: reason }), `${u.email} quedó suspendido.`);
  }

  function changeRole(u: User, role: UserRole) {
    if (role === u.role) return;
    if (!window.confirm(`¿Cambiar a ${u.email} de ${u.role} a ${role}?`)) return;
    return run(u, () => supabase.rpc("admin_set_role", { p_user: u.id, p_role: role }), `${u.email} ahora es ${role}.`);
  }

  async function viewAs(u: User) {
    setError(null);
    const { data, error } = await supabase.rpc("admin_user_detail", { p_user: u.id });
    if (error) return setError(friendlyError(error));
    setViewing({ user: u, detail: data as Detail });
  }

  return (
    <section>
      <h1>Usuarios</h1>
      <p className="muted">Busca, cambia el rol, suspende o revisa la cuenta de cualquier usuario.</p>
      <input type="search" placeholder="Buscar por correo o nombre" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Buscar usuario" />
      {notice && <p className="flash" role="status">{notice}</p>}
      {error && <p className="error">{error}</p>}

      {viewing && (
        <div className="card">
          <div className="row between">
            <h2>Ver como: {viewing.user.full_name ?? viewing.user.email}</h2>
            <button type="button" className="small" onClick={() => setViewing(null)}>Cerrar</button>
          </div>
          <p className="muted small">Solo lectura. Así está la cuenta de este usuario; no actúas en su nombre.</p>
          <p>
            Plan <strong>{viewing.detail.plan}</strong> · {viewing.detail.credits} créditos · pagado {mxn.format(viewing.detail.paid_mxn)} ·{" "}
            {viewing.detail.requests_sent} solicitudes enviadas · {viewing.detail.requests_received} recibidas · {viewing.detail.reports_against} reportes en su contra
          </p>
          {viewing.detail.properties.length > 0 && (
            <>
              <h3>Propiedades</h3>
              <ul>
                {viewing.detail.properties.map((p) => (
                  <li key={p.id}>
                    {p.title} <span className={`badge ${p.status}`}>{p.status}</span> <span className="muted small">{p.city} · {mxn.format(p.price)}</span>
                  </li>
                ))}
              </ul>
            </>
          )}
          {viewing.detail.posts.length > 0 && (
            <>
              <h3>Publicaciones</h3>
              <ul>
                {viewing.detail.posts.map((p) => (
                  <li key={p.id}>
                    {p.title} {p.hidden && <span className="badge hidden">oculta</span>}
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      )}

      {users === null && !error && <p>Cargando…</p>}
      {users && users.length === 0 && <p className="muted">No hay usuarios con esa búsqueda.</p>}
      {users && users.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Usuario</th>
              <th>Rol</th>
              <th>Plan</th>
              <th>Contenido</th>
              <th>Último acceso</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id}>
                <td>
                  {u.full_name ?? "—"}
                  <div className="muted small">{u.email}{!u.email_confirmed && " · sin confirmar"}</div>
                  {u.suspended && <span className="badge hidden">Suspendido{u.suspended_reason ? `: ${u.suspended_reason}` : ""}</span>}
                </td>
                <td>
                  <select value={u.role} disabled={busy !== null || u.role === "admin"} onChange={(e) => changeRole(u, e.target.value as UserRole)} aria-label={`Rol de ${u.email}`}>
                    {ROLES.map((r) => (
                      <option key={r} value={r}>{r}</option>
                    ))}
                  </select>
                </td>
                <td>{u.plan}</td>
                <td className="small">{u.properties} propiedades · {u.posts} publicaciones</td>
                <td className="small">{u.last_sign_in_at ? dateFmt.format(new Date(u.last_sign_in_at)) : "Nunca"}</td>
                <td className="actions">
                  <button type="button" className="small" onClick={() => viewAs(u)}>Ver como</button>
                  {u.role !== "admin" && (
                    <button type="button" className={`small ${u.suspended ? "" : "danger"}`} disabled={busy !== null} onClick={() => toggleSuspend(u)}>
                      {u.suspended ? "Reactivar" : "Suspender"}
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}
