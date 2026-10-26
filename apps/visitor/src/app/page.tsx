import Link from "next/link";
import PropertyCard from "@/components/PropertyCard";
import SearchForm from "@/components/SearchForm";
import { hasFilters, parseFilters, searchProperties } from "@/lib/search";

// Escaparate público (App 1) · ZAI-24: buscador con filtros.
// Solo aparecen propiedades publicadas (filtro explícito + RLS de ZAI-20).
export default async function Home({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = parseFilters(await searchParams);
  const properties = await searchProperties(filters);
  const filtered = hasFilters(filters);

  return (
    <main className="page">
      <h1>Encuentra tu propiedad</h1>
      <SearchForm filters={filters} />
      <p className="muted" aria-live="polite">
        {properties.length} {properties.length === 1 ? "propiedad" : "propiedades"}
      </p>
      {properties.length === 0 ? (
        <div className="card empty">
          <h2>Sin resultados</h2>
          <p>{filtered ? "No hay propiedades con esos filtros. Prueba con menos filtros o con otra ubicación." : "Todavía no hay propiedades publicadas."}</p>
          {filtered && (
            <Link href="/" className="button">
              Limpiar filtros
            </Link>
          )}
        </div>
      ) : (
        <ul className="cards">
          {properties.map((p) => (
            <PropertyCard key={p.id} property={p} />
          ))}
        </ul>
      )}
    </main>
  );
}
