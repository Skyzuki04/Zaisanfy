"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { CONTACT_KIND_LABEL, CONTACT_STATUS_LABEL, type ContactRequest } from "@zaisanfy/schemas";
import { browserSupabase } from "@/lib/supabase-browser";
import { useMiLista } from "@/lib/bookmarks";

/**
 * ZAI-33 (básico) · "Mis solicitudes": visitas y cotizaciones que envió el cliente, con su estado.
 * RLS: cada quien ve solo las suyas (y quien las recibe, en la Consola).
 */
type Row = ContactRequest & {
  property: { id: string; data: { title: string } } | null;
  creative: { id: string; display_name: string } | null;
};

const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

export default function MisSolicitudesPage() {
  const { ready, session } = useMiLista();
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const userId = session?.user.id;

  useEffect(() => {
    if (!userId) return;
    browserSupabase()
      .then((sb) =>
        sb
          .from("contact_requests")
          .select("*, property:properties(id, data), creative:creative_profiles(id, display_name)")
          .eq("requester_id", userId)
          .order("created_at", { ascending: false }),
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
        <h1>Mis solicitudes</h1>
        <div className="card empty">
          <p>Inicia sesión para ver las visitas y cotizaciones que has pedido.</p>
          <Link href="/entrar?next=/mis-solicitudes" className="button primary">
            Iniciar sesión o crear cuenta
          </Link>
        </div>
      </main>
    );
  }

  return (
    <main className="page">
      <h1>
        Mis <em>solicitudes</em>
      </h1>
      <p className="muted">Aquí ves a quién contactaste y en qué va cada solicitud.</p>
      {error && <p className="error">{error}</p>}
      {rows === null ? (
        <p>Cargando…</p>
      ) : rows.length === 0 ? (
        <div className="card empty">
          <h2>Todavía no has contactado a nadie</h2>
          <p>Cuando una propiedad te guste, usa “Contactar al vendedor” para agendar una visita. También puedes pedir cotizaciones a los creativos.</p>
          <div className="row">
            <Link href="/" className="button primary">
              Ver propiedades
            </Link>
            <Link href="/muro" className="button">
              Ver creativos en el muro
            </Link>
          </div>
        </div>
      ) : (
        <ul className="requests">
          {rows.map((r) => {
            const target =
              r.kind === "visita"
                ? r.property
                  ? { href: `/propiedad/${r.property.id}`, name: r.property.data.title }
                  : { href: null, name: "Propiedad que ya no está publicada" }
                : r.creative
                  ? { href: `/creativos/${r.creative.id}`, name: r.creative.display_name }
                  : { href: null, name: "Creativo que ya no está disponible" };
            return (
              <li key={r.id} className="card request">
                <div className="title-row">
                  <span className="eyebrow">{CONTACT_KIND_LABEL[r.kind]}</span>
                  <span className={`status-pill ${r.status}`}>{CONTACT_STATUS_LABEL[r.status]}</span>
                </div>
                <h2>{target.href ? <Link href={target.href}>{target.name}</Link> : target.name}</h2>
                <p className="muted">
                  Enviada el {dateFmt.format(new Date(r.created_at))} como <strong>{r.requester_name ?? "tu cuenta"}</strong>
                  {r.requester_email ? ` (${r.requester_email})` : ""}
                </p>
                {r.preferred_times && <p>Horario: {r.preferred_times}</p>}
                {r.message && <p className="request-msg">“{r.message}”</p>}
              </li>
            );
          })}
        </ul>
      )}
    </main>
  );
}
