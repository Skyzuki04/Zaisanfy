"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { ContactRequestInputSchema, type ContactKind } from "@zaisanfy/schemas";
import { browserSupabase } from "@/lib/supabase-browser";
import { signOut, useMiLista } from "@/lib/bookmarks";
import { useAccount } from "@/lib/role";

type Props = {
  kind: ContactKind;
  ownerId: string;
  propertyId?: string;
  creativeId?: string;
  postId?: string;
  operation?: "venta" | "renta";
  label?: string;
};

export default function ContactRequest({ kind, ownerId, propertyId, creativeId, postId, operation, label }: Props) {
  const { ready, session } = useMiLista();
  const pathname = usePathname();
  const router = useRouter();
  const { name, email } = useAccount();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const text = label ?? (kind === "visita" ? "Contactar al vendedor" : "Solicitar cotización");

  if (ready && session?.user.id === ownerId) return null;

  if (!ready || !session) {
    return (
      <div className="contact-cta">
        <Link href={`/entrar?next=${encodeURIComponent(pathname)}`} className="button primary contact-btn">
          {text}
        </Link>
        <small className="muted">Ver es libre. Para contactar te pedimos iniciar sesión, así sabemos quién escribe.</small>
      </div>
    );
  }

  if (sent) {
    return (
      <div className="card contact-sent" role="status">
        <h3>
          Solicitud <em>enviada</em>
        </h3>
        <p className="muted">
          {kind === "visita" ? "El vendedor" : "El creativo"} recibió tus datos y te contactará pronto. Puedes ver el estado en Mis solicitudes.
        </p>
        <div className="row">
          <Link href="/mis-solicitudes" className="button primary">
            Ver mis solicitudes
          </Link>
          <Link href={kind === "visita" ? "/" : "/muro"} className="button">
            {kind === "visita" ? "Seguir viendo propiedades" : "Seguir en el muro"}
          </Link>
        </div>
      </div>
    );
  }

  if (!open) {
    return (
      <div className="contact-cta">
        <button type="button" className="button primary contact-btn" onClick={() => setOpen(true)}>
          {text}
        </button>
      </div>
    );
  }

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    const f = Object.fromEntries(new FormData(e.currentTarget));
    const parsed = ContactRequestInputSchema.safeParse({
      ...f,
      kind,
      property_id: propertyId ?? null,
      creative_id: creativeId ?? null,
      post_id: postId ?? null,
    });
    if (!parsed.success) return setError(parsed.error.issues[0].message);
    setBusy(true);
    const sb = await browserSupabase();
    const { error } = await sb.from("contact_requests").insert(parsed.data);
    setBusy(false);
    if (error) return setError(error.message || "No se pudo enviar. Intenta de nuevo.");
    setSent(true);
  }

  return (
    <form className="card form contact-form" onSubmit={onSubmit} noValidate>
      <div className="title-row">
        <h3>{kind === "visita" ? "Agendar visita" : "Solicitar cotización"}</h3>
        <button type="button" className="link" onClick={() => setOpen(false)}>
          Cancelar
        </button>
      </div>
      <p className="sending-as">
        Enviarás esta solicitud como <strong>{name ?? "tu cuenta"}</strong>
        {email && <> ({email})</>} ·{" "}
        <button
          type="button"
          className="link"
          onClick={async () => {
            await signOut();
            router.push(`/entrar?next=${encodeURIComponent(pathname)}`);
          }}
        >
          ¿No eres tú? Cambiar de cuenta
        </button>
      </p>
      <p className="muted">{kind === "visita" ? "El vendedor" : "El creativo"} verá tu nombre y tu correo. El teléfono es opcional.</p>
      {kind === "visita" && (
        <label>
          Me interesa para
          <select name="operation" defaultValue={operation ?? ""}>
            <option value="venta">Comprar</option>
            <option value="renta">Rentar</option>
          </select>
        </label>
      )}
      <label>
        {kind === "visita" ? "¿Cuándo puedes visitarla?" : "¿Cuándo te pueden contactar?"}
        <input name="preferred_times" maxLength={200} placeholder="Ej. entre semana después de las 6 pm" />
      </label>
      <label>
        Teléfono o WhatsApp (opcional)
        <input name="phone" type="tel" autoComplete="tel" maxLength={30} placeholder="33 1234 5678" />
      </label>
      <label>
        Mensaje
        <textarea name="message" rows={3} maxLength={1000} placeholder={kind === "visita" ? "¿Algo que quieras preguntar?" : "Cuéntale qué necesitas: espacio, medidas, estilo…"} />
      </label>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <button className="button primary" disabled={busy}>
        {busy ? "Enviando…" : "Enviar solicitud"}
      </button>
    </form>
  );
}
