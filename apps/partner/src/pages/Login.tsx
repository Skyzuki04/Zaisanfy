import Logo from "../components/Logo";
import { useState, type FormEvent } from "react";
import { Navigate } from "react-router-dom";
import { SignInSchema, SignUpSchema } from "@zaisanfy/schemas";
import { useAuth } from "../auth/AuthProvider";

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";

/** ZAI-20 · Registro e inicio de sesión de vendedores y creativos. Los clientes se registran en el Escaparate. */
export default function Login() {
  const { session, signIn, signUp } = useAuth();
  const [mode, setMode] = useState<"entrar" | "registro">("entrar");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (session) return <Navigate to="/" replace />;

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setNotice(null);
    const form = Object.fromEntries(new FormData(e.currentTarget));
    setBusy(true);
    try {
      if (mode === "entrar") {
        const parsed = SignInSchema.safeParse(form);
        if (!parsed.success) return setError(parsed.error.issues[0].message);
        const err = await signIn(parsed.data);
        if (err) setError(err);
      } else {
        const parsed = SignUpSchema.safeParse(form);
        if (!parsed.success) return setError(parsed.error.issues[0].message);
        const { error: err, needsConfirmation } = await signUp(parsed.data);
        if (err) setError(err);
        else if (needsConfirmation) setNotice("Te mandamos un correo para confirmar tu cuenta. Después inicia sesión.");
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth-split">
      <aside className="auth-side">
        <Logo size={40} />
        <div>
          <span className="eyebrow">Consola de socios</span>
          <h2>
            Publica, muestra y <em>conecta</em>
          </h2>
          <p>Sube tus propiedades con recorrido 360° o tu portafolio de renders y planos, y llega a quien busca su próximo hogar.</p>
        </div>
        <ul className="auth-points">
          <li>Recorridos 360° en cada propiedad</li>
          <li>Portafolio para arquitectos y artistas 3D</li>
          <li>Tus datos protegidos por permisos</li>
        </ul>
      </aside>
    <div className="auth">
      <h1>
        {mode === "entrar" ? <>Bienvenido de <em>vuelta</em></> : <>Crea tu <em>cuenta</em></>}
      </h1>
      <div className="tabs">
        <button className={mode === "entrar" ? "active" : ""} onClick={() => setMode("entrar")} type="button">
          Iniciar sesión
        </button>
        <button className={mode === "registro" ? "active" : ""} onClick={() => setMode("registro")} type="button">
          Crear cuenta
        </button>
      </div>
      <form onSubmit={onSubmit} className="card form">
        {mode === "registro" && (
          <>
            <label>
              Nombre
              <input name="full_name" autoComplete="name" required />
            </label>
            <label>
              Soy
              <select name="role" defaultValue="vendedor">
                <option value="vendedor">Vendo o rento (agencia, desarrollador o dueño)</option>
                <option value="creativo">Ofrezco servicios creativos (arquitecto, interiorista o artista 3D)</option>
              </select>
            </label>
          </>
        )}
        <label>
          Correo
          <input name="email" type="email" autoComplete="email" required />
        </label>
        <label>
          Contraseña
          <input name="password" type="password" autoComplete={mode === "entrar" ? "current-password" : "new-password"} required />
        </label>
        {error && <p className="error">{error}</p>}
        {notice && <p className="notice">{notice}</p>}
        <button className="primary" disabled={busy}>
          {mode === "entrar" ? "Entrar" : "Crear cuenta"}
        </button>
      </form>
      <p className="muted auth-alt">
        {mode === "registro" ? "¿Buscas casa?" : "¿Eres cliente?"}{" "}
        <a href={`${visitorUrl}/entrar?modo=registro#zs_logout=1`}>Crea tu cuenta de cliente en el Escaparate</a>. Aquí solo se registran vendedores y creativos;
        con la misma cuenta entras a las dos apps.
      </p>
    </div>
    </div>
  );
}
