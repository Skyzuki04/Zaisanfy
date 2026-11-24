"use client";

import Link from "next/link";

// Si una página falla (sin internet, base de datos caída…), en vez de la pantalla de error de Next.js
// En producción Next.js oculta el mensaje real del servidor, por eso aquí va un texto fijo
export default function Error({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <main className="page">
      <div className="card state" role="alert">
        <span className="eyebrow">Algo salió mal</span>
        <h1>
          No pudimos cargar esta <em>página</em>
        </h1>
        <p className="muted">Revisa tu conexión a internet e inténtalo de nuevo.</p>
        <p className="muted small">Si sigue pasando, vuelve en unos minutos.</p>
        <div className="state-actions">
          <button type="button" className="button primary" onClick={() => reset()}>
            Reintentar
          </button>
          <Link href="/" className="button">
            Ir al inicio
          </Link>
        </div>
      </div>
    </main>
  );
}
