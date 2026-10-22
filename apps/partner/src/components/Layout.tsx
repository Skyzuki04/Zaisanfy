import { NavLink, Navigate, Outlet } from "react-router-dom";
import type { UserRole } from "@zaisanfy/schemas";
import { useAuth } from "../auth/AuthProvider";

/** Marco de la Consola: menú según el rol y protección de rutas. */
export default function Layout() {
  const { session, profile, loading, signOut } = useAuth();

  if (loading) return <p className="center">Cargando…</p>;
  if (!session) return <Navigate to="/entrar" replace />;
  if (!profile) return <p className="center">Cargando tu perfil…</p>;

  const role = profile.role;
  return (
    <div className="shell">
      <header className="topbar">
        <strong>Zaisanfy · Consola</strong>
        <nav>
          {(role === "vendedor" || role === "admin") && <NavLink to="/propiedades">Mis propiedades</NavLink>}
          {role === "creativo" && <NavLink to="/perfil">Mi perfil</NavLink>}
        </nav>
        <span className="who">
          {profile.full_name ?? session.user.email} · {role}
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

/** Deja pasar solo a los roles indicados. */
export function RequireRole({ roles, children }: { roles: UserRole[]; children: React.ReactNode }) {
  const { profile } = useAuth();
  if (!profile || !roles.includes(profile.role)) {
    return (
      <div className="card">
        <h2>Sin acceso</h2>
        <p>Esta sección es para: {roles.join(", ")}.</p>
      </div>
    );
  }
  return <>{children}</>;
}

/** Página de inicio según el rol. */
export function HomeRedirect() {
  const { profile } = useAuth();
  if (profile?.role === "vendedor" || profile?.role === "admin") return <Navigate to="/propiedades" replace />;
  if (profile?.role === "creativo") return <Navigate to="/perfil" replace />;
  return (
    <div className="card">
      <h2>Bienvenido</h2>
      <p>La Consola es para vendedores y creativos. Tu cuenta es de tipo "{profile?.role}".</p>
    </div>
  );
}
