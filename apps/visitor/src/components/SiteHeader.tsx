import Link from "next/link";

/** Menú del Escaparate. */
export default function SiteHeader() {
  return (
    <header className="site-header">
      <Link href="/" className="brand">
        Zaisanfy
      </Link>
      <nav>
        <Link href="/">Propiedades</Link>
        <Link href="/muro">Inspiración</Link>
      </nav>
    </header>
  );
}
