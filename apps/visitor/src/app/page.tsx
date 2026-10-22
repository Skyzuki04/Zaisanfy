import Link from "next/link";
import type { Property } from "@zaisanfy/schemas";
import { supabase } from "@/lib/supabase";
import { formatPrice, TYPE_LABEL } from "@/lib/format";

// Escaparate público (App 1). ZAI-21: solo se muestran las propiedades publicadas.
// El buscador con filtros llega en ZAI-24.
export const dynamic = "force-dynamic";

export default async function Home() {
  const { data } = await supabase
    .from("properties")
    .select("*")
    .eq("status", "published")
    .order("created_at", { ascending: false });
  const properties = (data as Property[]) ?? [];

  return (
    <main className="page">
      <h1>Propiedades</h1>
      {properties.length === 0 && <p>Todavía no hay propiedades publicadas.</p>}
      <ul className="cards">
        {properties.map((p) => (
          <li key={p.id} className="card">
            <h2>
              <Link href={`/propiedad/${p.id}`}>{p.data.title}</Link>
            </h2>
            <p className="muted">
              {TYPE_LABEL[p.data.propertyType]} en {p.data.operation} · {p.data.location.city}, {p.data.location.state}
            </p>
            <p className="price">{formatPrice(p.data)}</p>
          </li>
        ))}
      </ul>
    </main>
  );
}
