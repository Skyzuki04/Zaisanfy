"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOut, useMiLista } from "@/lib/bookmarks";
import { forgetAccount, useAccount } from "@/lib/role";
import { browserSupabase } from "@/lib/supabase-browser";
import ConsoleLink, { goToConsole } from "./ConsoleLink";

const CONSOLE_LINK: Record<string, { path: string; label: string }> = {
  creativo: { path: "/perfil", label: "Mi perfil" },
  vendedor: { path: "/propiedades", label: "Mis propiedades" },
  admin: { path: "/", label: "Mi consola" },
};
const ROLE_LABEL: Record<string, string> = { visitante: "Cliente", vendedor: "Vendedor", creativo: "Creativo", admin: "Admin" };

export default function AccountLinks() {
  const { ready, session, ids } = useMiLista();
  const { role, name, email, userId } = useAccount();
  const [upgradeError, setUpgradeError] = useState<string | null>(null);

  async function upgrade(newRole: "vendedor" | "creativo") {
    const what = newRole === "vendedor" ? "vendedor (publicar propiedades)" : "creativo (publicar tu portafolio)";
    if (!window.confirm(`¿Convertir tu cuenta en ${what}? Seguirás pudiendo usar Mi Lista y tus solicitudes.`)) return;
    setUpgradeError(null);
    const sb = await browserSupabase();
    const { error } = await sb.rpc("upgrade_role", { new_role: newRole });
    if (error) return setUpgradeError(error.message);
    if (userId) forgetAccount(userId);
    await goToConsole(newRole === "vendedor" ? "/propiedades" : "/perfil");
  }
  const pathname = usePathname();
  const menu = useRef<HTMLDetailsElement>(null);
  const consoleLink = session && role ? CONSOLE_LINK[role] : undefined;

  useEffect(() => {
    if (menu.current) menu.current.open = false;
  }, [pathname]);

  return (
    <>
      <Link href="/mi-lista">Mi Lista{ready && session && ids.size > 0 ? ` (${ids.size})` : ""}</Link>
      {consoleLink && (
        <ConsoleLink path={consoleLink.path} className="nav-console">
          {consoleLink.label}
        </ConsoleLink>
      )}
      {session ? (
        <details className="account-menu" ref={menu}>
          <summary aria-label={`Cuenta de ${name ?? email ?? ""}`}>
            <span className="avatar-initial" aria-hidden="true">
              {(name ?? email ?? "?").slice(0, 1).toUpperCase()}
            </span>
            <span className="account-name">{name ?? "Mi cuenta"}</span>
          </summary>
          <div className="account-panel">
            <p className="account-who">
              <strong>{name ?? "Mi cuenta"}</strong>
              <span>{email}</span>
              {role && <span className="role-chip">{ROLE_LABEL[role] ?? role}</span>}
            </p>
            <Link href="/mi-lista">Mi Lista</Link>
            <Link href="/mis-solicitudes">Mis solicitudes</Link>
            {role === "visitante" && (
              <div className="account-upgrade">
                <span>¿También quieres publicar?</span>
                <button type="button" className="link" onClick={() => upgrade("vendedor")}>
                  Quiero vender o rentar
                </button>
                <button type="button" className="link" onClick={() => upgrade("creativo")}>
                  Ofrecer mis servicios creativos
                </button>
                {upgradeError && <small className="error">{upgradeError}</small>}
              </div>
            )}
            {consoleLink && (
              <ConsoleLink path={consoleLink.path}>
                {consoleLink.label} en la Consola
              </ConsoleLink>
            )}
            <button type="button" className="link" onClick={signOut}>
              Salir
            </button>
          </div>
        </details>
      ) : (
        <>
          <Link href="/entrar?modo=registro&tipo=vendedor" className="nav-join">
            Únete como socio
          </Link>
          <Link href="/entrar">Entrar</Link>
        </>
      )}
    </>
  );
}
