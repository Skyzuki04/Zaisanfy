"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { friendlyError } from "@zaisanfy/schemas";
import { browserSupabase } from "@/lib/supabase-browser";
import { useMiLista } from "@/lib/bookmarks";

// ZAI-33 (antitrolls): reportar una propiedad o publicación. El admin la revisa en la Consola (migración 0018).
const REASONS = [
  ["fraude", "Fraude o pide dinero por fuera"],
  ["datos_falsos", "Datos o fotos falsos"],
  ["contenido_inapropiado", "Contenido inapropiado"],
  ["spam", "Spam o repetido"],
  ["otro", "Otro"],
] as const;

type Props = { ownerId: string; propertyId?: string; postId?: string };

export default function ReportButton({ ownerId, propertyId, postId }: Props) {
  const { ready, session } = useMiLista();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  if (!ready || session?.user.id === ownerId) return null;
  if (sent) return <p className="muted small report-sent" role="status">Gracias. Lo revisaremos pronto.</p>;
  if (!session)
    return (
      <Link href={`/entrar?next=${encodeURIComponent(pathname)}`} className="report-link">
        Reportar
      </Link>
    );
  if (!open)
    return (
      <button type="button" className="report-link" onClick={() => setOpen(true)}>
        Reportar
      </button>
    );

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    const f = new FormData(e.currentTarget);
    const details = String(f.get("details") ?? "").trim();
    if (details.length > 500) return setError("Máximo 500 caracteres.");
    setBusy(true);
    const sb = await browserSupabase();
    const { error } = await sb.from("reports").insert({
      property_id: propertyId ?? null,
      post_id: postId ?? null,
      reason: String(f.get("reason")),
      details: details || null,
    });
    setBusy(false);
    if (error?.code === "23505") return setSent(true); // ya lo había reportado
    if (error) return setError(friendlyError(error));
    setSent(true);
  }

  return (
    <form className="card report-form" onSubmit={onSubmit}>
      <label>
        ¿Qué pasa?
        <select name="reason" defaultValue="fraude">
          {REASONS.map(([v, label]) => (
            <option key={v} value={v}>
              {label}
            </option>
          ))}
        </select>
      </label>
      <label>
        Cuéntanos más (opcional)
        <textarea name="details" rows={2} maxLength={500} />
      </label>
      {error && <p className="error">{error}</p>}
      <div className="row">
        <button type="submit" className="button" disabled={busy}>
          {busy ? "Enviando…" : "Enviar reporte"}
        </button>
        <button type="button" className="report-link" onClick={() => setOpen(false)}>
          Cancelar
        </button>
      </div>
    </form>
  );
}
