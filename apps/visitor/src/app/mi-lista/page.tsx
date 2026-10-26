"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import type { Property } from "@zaisanfy/schemas";
import PropertyCard from "@/components/PropertyCard";
import { browserSupabase } from "@/lib/supabase-browser";
import { toggleBookmark, useMiLista } from "@/lib/bookmarks";

/**
 * ZAI-31 · RF-VIS-04 · "Mi Lista": propiedades guardadas por el visitante.
 * RLS: cada quien ve solo su lista. Si una propiedad ya no está publicada, se avisa y se puede quitar.
 */
type Row = { property_id: string; created_at: string; property: Property | null };

export default function MiListaPage() {
  const { ready, session, ids } = useMiLista();
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const userId = session?.user.id;

  useEffect(() => {
    if (!userId) return;
    browserSupabase()
      .then((sb) =>
        sb.from("bookmarks").select("property_id, created_at, property:properties(*)").order("created_at", { ascending: false }),
      )
      .then(({ data, error }) => {
        if (error) setError(error.message);
        setRows((data as unknown as Row[]) ?? []);
      });
  }, [userId]);

  if (!ready) return <main className="page"><p>Cargando…</p></main>;
  if (!session) {
    return (
      <main className="page">
        <h1>Mi Lista</h1>
        <div className="card empty">
          <p>Inicia sesión para guardar propiedades y verlas aquí.</p>
          <Link href="/entrar?next=/mi-lista" className="button primary">
            Iniciar sesión o crear cuenta
          </Link>
        </div>
      </main>
    );
  }

  // Lo que se quita con el corazón desaparece al momento
  const visible = (rows ?? []).filter((r) => ids.has(r.property_id));

  return (
    <main className="page">
      <h1>Mi Lista</h1>
      {error && <p className="error">{error}</p>}
      {rows === null ? (
        <p>Cargando…</p>
      ) : visible.length === 0 ? (
        <div className="card empty">
          <h2>Tu lista está vacía</h2>
          <p>Toca el corazón de una propiedad para guardarla aquí.</p>
          <Link href="/" className="button">
            Buscar propiedades
          </Link>
        </div>
      ) : (
        <>
          <p className="muted" aria-live="polite">
            {visible.length} {visible.length === 1 ? "propiedad guardada" : "propiedades guardadas"}
          </p>
          <ul className="cards">
            {visible.map((r) =>
              r.property ? (
                <PropertyCard key={r.property_id} property={r.property} />
              ) : (
                <li key={r.property_id} className="card">
                  <h2>Ya no está disponible</h2>
                  <p className="muted">El vendedor la cerró o la ocultó.</p>
                  <button type="button" className="button" onClick={() => toggleBookmark(r.property_id)}>
                    Quitar de la lista
                  </button>
                </li>
              ),
            )}
          </ul>
        </>
      )}
    </main>
  );
}
