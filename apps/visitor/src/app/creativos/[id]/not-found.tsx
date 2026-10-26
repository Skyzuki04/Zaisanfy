import Link from "next/link";

export default function NotFound() {
  return (
    <main className="page">
      <h1>Este creativo no existe</h1>
      <Link href="/">Volver a Zaisanfy</Link>
    </main>
  );
}
