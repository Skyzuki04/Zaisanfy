import Link from "next/link";

export default function NotFound() {
  return (
    <main className="page">
      <h1>Esta publicación no existe</h1>
      <p>Puede que el creativo la haya borrado.</p>
      <Link href="/">Ir al inicio</Link>
    </main>
  );
}
