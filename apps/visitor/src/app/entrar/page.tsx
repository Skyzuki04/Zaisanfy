"use client";

import { Suspense, useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { SignInSchema, SignUpSchema } from "@zaisanfy/schemas";
import { browserSupabase } from "@/lib/supabase-browser";
import { useMiLista } from "@/lib/bookmarks";

/**
 * ZAI-31 · Registro e inicio de sesión del visitante en el Escaparate (para guardar en "Mi Lista").
 * Las cuentas creadas aquí siempre son de rol visitante. Vendedores y creativos entran por la Consola.
 */
export default function EntrarPage() {
  return (
    <Suspense>
      <Entrar />
    </Suspense>
  );
}

function Entrar() {
  const router = useRouter();
  const params = useSearchParams();
  const raw = params.get("next") ?? "/mi-lista";
  const next = raw.startsWith("/") && !raw.startsWith("//") ? raw : "/mi-lista"; // solo rutas internas
  const { session } = useMiLista();
  const [mode, setMode] = useState<"entrar" | "registro">("entrar");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (session) router.replace(next);
  }, [session, next, router]);

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
        const parsed = SignUpSchema.safeParse({ ...form, role: "visitante" });
        if (!parsed.success) return setError(parsed.error.issues[0].message);
        const { email, password, full_name } = parsed.data;
        const { data, error } = await sb.auth.signUp({
          email,
          password,
          options: { data: { role: "visitante", full_name }, emailRedirectTo: `${window.location.origin}/entrar?next=${encodeURIComponent(next)}` },
        });
        if (error) setError(error.message);
        else if (!data.session) setNotice("Te mandamos un correo para confirmar tu cuenta. Después inicia sesión.");
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="page auth">
      <h1>{mode === "entrar" ? "Inicia sesión" : "Crea tu cuenta"}</h1>
      <p className="muted">Guarda propiedades en Mi Lista para verlas después desde cualquier dispositivo.</p>
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
          <label>
            Nombre
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
          {busy ? "Un momento…" : mode === "entrar" ? "Entrar" : "Crear cuenta"}
        </button>
      </form>
      <p className="muted">
        ¿Vendes propiedades o eres creativo? Entra en la <a href={process.env.NEXT_PUBLIC_PARTNER_URL ?? "http://localhost:5173"}>Consola de socios</a>.
      </p>
      <p>
        <Link href="/">← Seguir viendo propiedades</Link>
      </p>
    </main>
  );
}
