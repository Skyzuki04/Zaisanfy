import { Link, NavLink, Navigate, Outlet } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";
import type { UserRole } from "@zaisanfy/schemas";
import { useAuth } from "../auth/AuthProvider";
import Logo from "./Logo";

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";

export function withSession(e: React.MouseEvent<HTMLAnchorElement>, session: Session | null) {
  if (!session) return;
  const a = e.currentTarget;
  const base = a.href.split("#")[0];
  a.href = `${base}#zs_at=${encodeURIComponent(session.access_token)}&zs_rt=${encodeURIComponent(session.refresh_token)}`;
  setTimeout(() => (a.href = base), 0);
}

const ROLE_LABEL: Record<UserRole, string> = { vendedor: "Vendedor", creativo: "Creativo", admin: "Admin", visitante: "Visitante" };

export default function Layout() {
  const { session, profile, loading, signOut } = useAuth();

  if (loading) return <p className="center">Cargando…</p>;
  if (!session) return <Navigate to="/entrar" replace />;
  if (!profile) return <p className="center">Cargando tu perfil…</p>;

  const role = profile.role;
  return (
    <div className="shell">
      <header className="topbar">
        <span className="row"><Logo size={30} /><span className="console-tag">Consola</span></span>
        <nav>
          {(role === "vendedor" || role === "admin") && <NavLink to="/propiedades">Mis propiedades</NavLink>}
          {role === "creativo" && <NavLink to="/perfil">Mi perfil</NavLink>}
          {role === "creativo" && <NavLink to="/portafolio">Mi portafolio</NavLink>}
          {role !== "visitante" && <NavLink to="/solicitudes">Solicitudes</NavLink>}
        </nav>
        <a href={visitorUrl} target="_blank" rel="noreferrer" className="to-site" onClick={(e) => withSession(e, session)}>
          Ver Escaparate ↗
        </a>
        <span className="who">
          <span className="who-name" title={session.user.email}>
            {profile.full_name ?? session.user.email}
          </span>
          <span className="role-badge">{ROLE_LABEL[role]}</span>
          <button onClick={signOut} className="link">
            Salir
          </button>
        </span>
      </header>
      <main className="content">
        <Outlet />
      </main>
    </div>
  );
}

export function RequireRole({ roles, children }: { roles: UserRole[]; children: React.ReactNode }) {
  const { profile } = useAuth();
  if (!profile || !roles.includes(profile.role)) {
    return (
      <div className="card empty-state">
        <h2>Sin acceso</h2>
        <p className="muted">Esta sección es para: {roles.map((r) => ROLE_LABEL[r].toLowerCase()).join(", ")}.</p>
        <Link to="/" className="button primary">
          Ir a mi inicio
        </Link>
      </div>
    );
  }
  return <>{children}</>;
}

export function HomeRedirect() {
  const { profile } = useAuth();
  if (profile?.role === "vendedor" || profile?.role === "admin") return <Navigate to="/propiedades" replace />;
  if (profile?.role === "creativo") return <Navigate to="/perfil" replace />;
  const { session, signOut } = useAuth();
  return (
    <div className="card empty-state">
      <h2>
        Tu cuenta es de <em>cliente</em>
      </h2>
      <p className="muted">
        La Consola es para vendedores y creativos. Como cliente puedes ver propiedades, guardarlas en Mi Lista y contactar a vendedores desde el Escaparate.
      </p>
      <div className="row">
        <a href={visitorUrl} className="button primary" onClick={(e) => withSession(e, session)}>
          Ir al Escaparate
        </a>
        <button type="button" onClick={signOut}>
          Salir y entrar con otra cuenta
        </button>
      </div>
    </div>
  );
}
