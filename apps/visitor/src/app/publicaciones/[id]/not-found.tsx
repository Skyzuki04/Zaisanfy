import Link from "next/link";

export default function NotFound() {
  return (
    <main className="page">
      <h1>Esta publicación no existe</h1>
      <p>Puede que el creativo la haya borrado.</p>
      <Link href="/muro" className="button primary">Ver más en el muro</Link>
    </main>
  );
}
