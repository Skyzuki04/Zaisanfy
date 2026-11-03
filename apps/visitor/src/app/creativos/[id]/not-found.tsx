import Link from "next/link";

export default function NotFound() {
  return (
    <main className="page">
      <h1>Este creativo no existe</h1>
      <Link href="/muro" className="button primary">Ver creativos en el muro</Link>
    </main>
  );
}
