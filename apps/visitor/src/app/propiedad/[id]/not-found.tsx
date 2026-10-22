import Link from "next/link";

export default function NotFound() {
  return (
    <main className="page">
      <h1>Esta propiedad no está disponible</h1>
      <p>Puede que ya no esté publicada.</p>
      <Link href="/">Ver otras propiedades</Link>
    </main>
  );
}
