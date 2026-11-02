import Link from "next/link";
import AccountLinks from "./AccountLinks";

/** Menú del Escaparate. */
export default function SiteHeader() {
  return (
    <div className="header-wrap">
    <header className="site-header">
      <Link href="/" className="brand">
        zaisan<em>fy</em>
      </Link>
      <nav>
        <Link href="/">Propiedades</Link>
        <Link href="/muro">Inspiración</Link>
        <AccountLinks />
      </nav>
    </header>
    </div>
  );
}
