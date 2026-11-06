"use client";

import { Suspense, useEffect, useState, type FormEvent, type ReactNode } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { SignInSchema, SignUpSchema, type SignUpRole } from "@zaisanfy/schemas";
import { browserSupabase } from "@/lib/supabase-browser";
import { useAccount } from "@/lib/role";
import { goToConsole } from "@/components/ConsoleLink";

export default function EntrarPage() {
  return (
    <Suspense>
      <Entrar />
    </Suspense>
  );
}

const ACCOUNT_TYPES: { role: SignUpRole; title: string; text: string; icon: ReactNode }[] = [
  {
    role: "visitante",
    title: "Busco casa",
    text: "Contacta vendedores, agenda visitas, pide cotizaciones y guarda en Mi Lista.",
    icon: <path d="M4 11 12 4l8 7M6 10v9h12v-9M10 19v-5h4v5" />,
  },
  {
    role: "vendedor",
    title: "Vendo o rento",
    text: "Agencias, desarrolladores y dueños: publica propiedades con recorrido 360° y recibe solicitudes.",
    icon: <path d="M4 20V9l8-5 8 5v11M9 20v-6h6v6M3 20h18M15 8h3" />,
  },
  {
    role: "creativo",
    title: "Ofrezco servicios creativos",
    text: "Arquitectos, interioristas y artistas 3D: muestra tu portafolio y recibe cotizaciones.",
    icon: <path d="M4 20 15 9l-2-2L2 18zM14 4l6 6M17 3l4 4M9 20h11" />,
  },
];

function reasonFor(next: string | null, mode: "entrar" | "registro") {
  const verb = mode === "registro" ? "Crea tu cuenta" : "Inicia sesión";
  if (!next) return null;
  if (next.startsWith("/propiedad/")) return `${verb} para contactar al vendedor o guardar esta propiedad. Al terminar regresas a ella.`;
  if (next.startsWith("/creativos/") || next.startsWith("/publicaciones/")) return `${verb} para pedir una cotización. Al terminar regresas a donde estabas.`;
  if (next.startsWith("/mi-lista")) return `${verb} para guardar propiedades en Mi Lista.`;
  if (next.startsWith("/mis-solicitudes")) return `${verb} para ver tus solicitudes de visita y cotización.`;
  return null;
}

function Entrar() {
  const router = useRouter();
  const params = useSearchParams();
  const raw = params.get("next");
  const next = raw && raw.startsWith("/") && !raw.startsWith("//") ? raw : null;
  const preset = params.get("tipo");
  const { ready, userId, role } = useAccount();
  const [mode, setMode] = useState<"entrar" | "registro">(params.get("modo") === "registro" || preset ? "registro" : "entrar");
  const [accountType, setAccountType] = useState<SignUpRole>(preset === "vendedor" || preset === "creativo" ? preset : "visitante");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const isSocio = role === "vendedor" || role === "creativo" || role === "admin";

  useEffect(() => {
    if (!ready || !userId || !role) return;
    if (next || !isSocio) {
      router.replace(next ?? "/");
      return;
    }
    const t = setTimeout(() => void goToConsole(role === "creativo" ? "/perfil" : "/propiedades"), 1500);
    return () => clearTimeout(t);
  }, [ready, userId, role, isSocio, next, router]);

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setNotice(null);
    const form = Object.fromEntries(new FormData(e.currentTarget));
    const sb = await browserSupabase();
    setBusy(true);
    try {
      if (mode === "entrar") {
        const parsed = SignInSchema.safeParse(form);
        if (!parsed.success) return setError(parsed.error.issues[0].message);
        const { error } = await sb.auth.signInWithPassword(parsed.data);
        if (error) setError(error.message === "Invalid login credentials" ? "Correo o contraseña incorrectos" : error.message);
      } else {
        const parsed = SignUpSchema.safeParse({ ...form, role: accountType });
        if (!parsed.success) return setError(parsed.error.issues[0].message);
        const { email, password, full_name, role } = parsed.data;
        const back = `${window.location.origin}/entrar${next ? `?next=${encodeURIComponent(next)}` : ""}`;
        const { data, error } = await sb.auth.signUp({ email, password, options: { data: { role, full_name }, emailRedirectTo: back } });
        // Con confirmación de correo, Supabase responde sin error y con identities vacío si el correo ya existe
        if (error?.message === "User already registered" || data.user?.identities?.length === 0) setError("Ese correo ya tiene una cuenta. Inicia sesión.");
        else if (error) setError(error.message);
        else if (!data.session) {
          setNotice("Te mandamos un correo para confirmar tu cuenta. Ábrelo, confirma y después inicia sesión aquí.");
          setMode("entrar");
        }
      }
    } finally {
      setBusy(false);
    }
  }

  if (ready && userId && isSocio && !next) {
    return (
      <main className="page auth">
        <div className="card going-console" role="status">
          <h1>
            Te llevamos a tu <em>Consola</em>
          </h1>
          <p className="muted">Ahí publicas, editas y atiendes tus solicitudes.</p>
          <div className="row">
            <button type="button" className="button primary" onClick={() => void goToConsole(role === "creativo" ? "/perfil" : "/propiedades")}>
              Ir ahora
            </button>
            <Link href="/" className="button">
              Mejor quedarme en el Escaparate
            </Link>
          </div>
        </div>
      </main>
    );
  }

  const reason = reasonFor(next, mode);

  return (
    <main className="page auth">
      {reason && <p className="auth-reason">{reason}</p>}
      <h1>
        {mode === "entrar" ? (
          <>
            Inicia <em>sesión</em>
          </>
        ) : (
          <>
            Crea tu <em>cuenta</em>
          </>
        )}
      </h1>
      <p className="muted">
        {mode === "entrar"
          ? "Una sola cuenta para todo Zaisanfy: clientes, vendedores y creativos entran aquí."
          : "Es gratis. Para ver propiedades no necesitas cuenta; la necesitas para contactar, publicar o guardar."}
      </p>
      <div className="tabs" role="tablist">
        <button type="button" role="tab" aria-selected={mode === "entrar"} className={mode === "entrar" ? "active" : ""} onClick={() => setMode("entrar")}>
          Iniciar sesión
        </button>
        <button type="button" role="tab" aria-selected={mode === "registro"} className={mode === "registro" ? "active" : ""} onClick={() => setMode("registro")}>
          Crear cuenta
        </button>
      </div>
      <form onSubmit={onSubmit} className="card form" noValidate>
        {mode === "registro" && (
          <fieldset className="account-types">
            <legend>¿Qué quieres hacer en Zaisanfy?</legend>
            {ACCOUNT_TYPES.map((t) => (
              <label key={t.role} className={`account-type ${accountType === t.role ? "selected" : ""}`}>
                <input type="radio" name="account_type" value={t.role} checked={accountType === t.role} onChange={() => setAccountType(t.role)} />
                <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  {t.icon}
                </svg>
                <span>
                  <strong>{t.title}</strong>
                  <small>{t.text}</small>
                </span>
              </label>
            ))}
            <small className="muted">Después puedes volverte vendedor o creativo desde tu cuenta.</small>
          </fieldset>
        )}
        {mode === "registro" && (
          <label>
            {accountType === "visitante" ? "Nombre" : "Nombre o empresa / estudio"}
            <input name="full_name" autoComplete="name" />
          </label>
        )}
        <label>
          Correo
          <input name="email" type="email" autoComplete="email" />
        </label>
        <label>
          Contraseña
          <input name="password" type="password" autoComplete={mode === "entrar" ? "current-password" : "new-password"} />
        </label>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        {notice && <p className="notice">{notice}</p>}
        <button className="button primary" disabled={busy}>
          {busy ? "Un momento…" : mode === "entrar" ? "Entrar" : accountType === "visitante" ? "Crear cuenta" : "Crear cuenta de socio"}
        </button>
      </form>
      <p>
        <Link href={next ?? "/"}>← {next ? "Regresar sin entrar" : "Seguir viendo propiedades"}</Link>
      </p>
    </main>
  );
}
