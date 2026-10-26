"use client";

import Link from "next/link";
import { signOut, useMiLista } from "@/lib/bookmarks";

/** ZAI-31 · Enlaces de la cuenta del visitante en el menú. */
export default function AccountLinks() {
  const { ready, session, ids } = useMiLista();
  return (
    <>
      <Link href="/mi-lista">Mi Lista{ready && session && ids.size > 0 ? ` (${ids.size})` : ""}</Link>
      {/* "Entrar" se pinta desde el servidor para que el menú no brinque al cargar la sesión */}
      {session ? (
        <button type="button" className="link" onClick={signOut}>
          Salir
        </button>
      ) : (
        <Link href="/entrar">Entrar</Link>
      )}
    </>
  );
}
