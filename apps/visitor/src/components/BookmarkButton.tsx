"use client";

import { useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { toggleBookmark, useMiLista } from "@/lib/bookmarks";

/** ZAI-31 · Botón de corazón: guarda o quita la propiedad de "Mi Lista". Sin sesión, manda a iniciar sesión. */
export default function BookmarkButton({ propertyId, title, className = "" }: { propertyId: string; title: string; className?: string }) {
  const { ready, session, ids } = useMiLista();
  const router = useRouter();
  const pathname = usePathname();
  const [error, setError] = useState<string | null>(null);
  const saved = ids.has(propertyId);

  async function onClick() {
    if (!session) {
      router.push(`/entrar?next=${encodeURIComponent(pathname)}`);
      return;
    }
    setError(await toggleBookmark(propertyId));
  }

  return (
    <>
      <button
        type="button"
        className={`heart ${saved ? "saved" : ""} ${className}`}
        onClick={onClick}
        disabled={!ready}
        aria-pressed={saved}
        aria-label={saved ? `Quitar "${title}" de Mi Lista` : `Guardar "${title}" en Mi Lista`}
        title={saved ? "Quitar de Mi Lista" : "Guardar en Mi Lista"}
        data-testid="heart"
      >
        <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
          <path d="M12 21s-7.5-4.6-9.6-9.2C.9 8.4 3 4.5 6.7 4.5c2.1 0 3.5 1.1 4.3 2.4.8-1.3 2.2-2.4 4.3-2.4 3.7 0 5.8 3.9 4.3 7.3C19.5 16.4 12 21 12 21z" />
        </svg>
      </button>
      {error && (
        <span role="alert" className="error">
          {error}
        </span>
      )}
    </>
  );
}
