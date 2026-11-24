import { useEffect, useState, type FormEvent } from "react";
import { BrowserRouter, NavLink, Navigate, Route, Routes } from "react-router-dom";
import type { Session } from "@supabase/supabase-js";
import { SignInSchema } from "@zaisanfy/schemas";
import { supabase } from "./lib/supabase";
import Logo from "./components/Logo";
import Turnstile from "./components/Turnstile";
import Reportes from "./pages/Reportes";
import Usuarios from "./pages/Usuarios";
import Seo from "./pages/Seo";
import Metricas from "./pages/Metricas";

// App 3 del SRS: Núcleo Administrativo (back-office). Solo entra el rol admin; la base lo vuelve a revisar en cada función.
const captchaKey = import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined;

type State = { session: Session | null; isAdmin: boolean; name: string | null; loading: boolean };

export default function App() {
  const [state, setState] = useState<State>({ session: null, isAdmin: false, name: null, loading: true });

  useEffect(() => {
    async function check(session: Session | null) {
      if (!session) return setState({ session: null, isAdmin: false, name: null, loading: false });
      const { data } = await supabase.from("profiles").select("role, full_name").eq("id", session.user.id).maybeSingle();
      setState({ session, isAdmin: data?.role === "admin", name: data?.full_name ?? session.user.email ?? null, loading: false });
    }
    supabase.auth.getSession().then(({ data }) => check(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setTimeout(() => check(s), 0));
    return () => sub.subscription.unsubscribe();
  }, []);

  if (state.loading) return <p className="center">Cargando…</p>;
  if (!state.session) return <Login />;
  if (!state.isAdmin) return <NoAccess />;

  return (
    <BrowserRouter>
      <div className="shell">
        <header className="topbar">
          <span className="row"><Logo size={30} /><span className="console-tag">Admin</span></span>
          <nav>
            <NavLink to="/usuarios">Usuarios</NavLink>
            <NavLink to="/reportes">Reportes</NavLink>
            <NavLink to="/seo">SEO</NavLink>
            <NavLink to="/metricas">Métricas</NavLink>
          </nav>
          <span className="who">
            <span className="who-name">{state.name}</span>
            <span className="role-badge">Admin</span>
            <button className="link" onClick={() => supabase.auth.signOut()}>Salir</button>
          </span>
        </header>
        <main className="content">
          <Routes>
            <Route index element={<Navigate to="/usuarios" replace />} />
            <Route path="/usuarios" element={<Usuarios />} />
            <Route path="/reportes" element={<Reportes />} />
            <Route path="/seo" element={<Seo />} />
            <Route path="/metricas" element={<Metricas />} />
            <Route path="*" element={<Navigate to="/usuarios" replace />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}

function Login() {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [captcha, setCaptcha] = useState<string | null>(null);
  const [captchaReset, setCaptchaReset] = useState(0);

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    const parsed = SignInSchema.safeParse(Object.fromEntries(new FormData(e.currentTarget)));
    if (!parsed.success) return setError(parsed.error.issues[0].message);
    if (captchaKey && !captcha) return setError("Completa la verificación de que no eres un robot.");
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({ ...parsed.data, options: { captchaToken: captcha ?? undefined } });
    setBusy(false);
    if (error) {
      setError(/captcha/i.test(error.message) ? "La verificación de robot falló. Intenta de nuevo." : "Correo o contraseña incorrectos");
      setCaptchaReset((n) => n + 1);
    }
  }

  return (
    <div className="auth-page">
      <form className="card form auth" onSubmit={onSubmit} noValidate>
        <Logo size={36} light={false} />
        <h1>Núcleo Administrativo</h1>
        <p className="muted">Solo para el equipo de Zaisanfy.</p>
        <label>
          Correo
          <input name="email" type="email" autoComplete="email" required />
        </label>
        <label>
          Contraseña
          <input name="password" type="password" autoComplete="current-password" required />
        </label>
        {captchaKey && <Turnstile siteKey={captchaKey} onToken={setCaptcha} resetKey={captchaReset} />}
        {error && <p className="error">{error}</p>}
        <button className="primary" disabled={busy}>{busy ? "Entrando…" : "Entrar"}</button>
      </form>
    </div>
  );
}

function NoAccess() {
  return (
    <div className="auth-page">
      <div className="card empty-state">
        <h2>Sin <em>acceso</em></h2>
        <p className="muted">Esta app es solo para administradores de Zaisanfy.</p>
        <button onClick={() => supabase.auth.signOut()}>Salir</button>
      </div>
    </div>
  );
}
