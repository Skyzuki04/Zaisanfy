import Link from "next/link";

export const metadata = { title: "Página no encontrada · Zaisanfy", robots: { index: false } };

export default function NotFound() {
  return (
    <main className="page">
      <div className="state">
        <span className="state-code" aria-hidden="true">404</span>
        <h1>
          Esta página no <em>existe</em>
        </h1>
        <p className="muted">Puede que la propiedad se haya vendido o que el link esté mal escrito.</p>
        <div className="state-actions">
          <Link href="/" className="button primary">
            Ver propiedades
          </Link>
          <Link href="/muro" className="button">
            Inspiración
          </Link>
        </div>
      </div>
    </main>
  );
}
