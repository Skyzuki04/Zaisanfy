"use client";

import { useAccount } from "@/lib/role";
import ConsoleLink from "./ConsoleLink";

/**
 * Accesos del dueño en su perfil público: editar el perfil o subir trabajo en la Consola.
 * Es un componente cliente para que la página siga en caché (ISR) para todos los demás.
 */
export default function CreativeOwnerActions({ creativeId, variant = "header" }: { creativeId: string; variant?: "header" | "empty" }) {
  const { userId } = useAccount();
  if (userId !== creativeId) return null;

  if (variant === "empty") {
    return (
      <div className="card owner-cta">
        <h3>
          Tu portafolio está <em>vacío</em>
        </h3>
        <p className="muted">Sube tu primer render, plano o idea para que aparezca aquí y en el muro de inspiración.</p>
        <ConsoleLink path="/portafolio/nueva" className="button primary">
          + Subir mi primer trabajo
        </ConsoleLink>
      </div>
    );
  }

  return (
    <div className="owner-actions">
      <span className="eyebrow">Este es tu perfil</span>
      <div className="row">
        <ConsoleLink path="/portafolio/nueva" className="button primary">
          + Subir trabajo
        </ConsoleLink>
        <ConsoleLink path="/perfil" className="button ghost">
          Editar perfil
        </ConsoleLink>
        <ConsoleLink path="/portafolio" className="button ghost">
          Mi portafolio
        </ConsoleLink>
      </div>
    </div>
  );
}
