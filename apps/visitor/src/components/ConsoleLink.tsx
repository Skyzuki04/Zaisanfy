"use client";

import type { MouseEvent, ReactNode } from "react";
import { browserSupabase } from "@/lib/supabase-browser";
import { PARTNER_URL } from "@/lib/role";

/** Cruza a la Consola con la sesión de aquí (o con el aviso de que no hay sesión). */
export async function goToConsole(path = "/") {
  const href = `${PARTNER_URL}${path}`;
  const { data } = await (await browserSupabase()).auth.getSession();
  const s = data.session;
  window.location.href = s ? `${href}#zs_at=${encodeURIComponent(s.access_token)}&zs_rt=${encodeURIComponent(s.refresh_token)}` : `${href}#zs_logout=1`;
}

/**
 * Enlace a la Consola que le pasa la sesión del Escaparate.
 * Son orígenes distintos (cada uno guarda su sesión), así que sin esto la Consola
 * podría seguir abierta con otra cuenta. Los tokens van en el hash: no llegan a ningún servidor
 * y la Consola los borra de la barra en cuanto los lee. Solo pasa al dar clic, nunca en silencio.
 * Sin sesión aquí se manda #zs_logout=1 para que la Consola también cierre la suya.
 */
export default function ConsoleLink({ path = "/", className, children }: { path?: string; className?: string; children: ReactNode }) {
  const href = `${PARTNER_URL}${path}`;

  function onClick(e: MouseEvent<HTMLAnchorElement>) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
    e.preventDefault();
    void goToConsole(path);
  }

  return (
    <a href={href} className={className} onClick={onClick}>
      {children}
    </a>
  );
}
