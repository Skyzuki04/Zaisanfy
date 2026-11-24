import Link from "next/link";
import PropertyCard from "@/components/PropertyCard";
import SearchForm from "@/components/SearchForm";
import IsochroneSearch, { type MapProperty } from "@/components/IsochroneSearch";
import { orderedPhotos } from "@/lib/photos";
import { cld } from "@/lib/cloudinary";
import { hasFilters, parseFilters, searchProperties, toQuery } from "@/lib/search";
import { getIsochrone } from "@/lib/isochrone";
import { getSponsored } from "@/lib/ads";

export default async function Home({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = parseFilters(await searchParams);
  // ZAI-38: si el visitante eligió punto y tiempo, primero se calcula la zona y luego se busca dentro
  const isochrone = filters.cerca && filters.tiempo ? await getIsochrone(filters.cerca, filters.tiempo) : null;
  const [found, allSponsored] = await Promise.all([searchProperties(filters, isochrone?.zone), getSponsored("buscador", 3, filters)]);
  // Con zona, un anuncio solo sale si su propiedad también está dentro
  const foundIds = new Set(found.map((p) => p.id));
  const sponsored = isochrone ? allSponsored.filter((s) => foundIds.has(s.property.id)) : allSponsored;
  // El anuncio va primero y no se repite abajo
  const sponsoredIds = new Set(sponsored.map((s) => s.property.id));
  const organic = found.filter((p) => !sponsoredIds.has(p.id));
  const properties = [...sponsored.map((s) => s.property), ...organic];
  const filtered = hasFilters(filters);
  const heroPhoto = properties.map((p) => orderedPhotos(p)[0]).find(Boolean);
  const onMap: MapProperty[] = properties.flatMap((p) => {
    const { lat, lng } = p.data.location;
    return lat !== undefined && lng !== undefined ? [{ id: p.id, title: p.data.title, lat, lng }] : [];
  });

  return (
    <>
      <section className={`hero ${heroPhoto ? "with-photo" : ""}`}>
        {heroPhoto && <img className="hero-photo" src={cld(heroPhoto, 1600)} alt="" fetchPriority="high" />}
        <div className="hero-orbit" aria-hidden="true" />
        <div className="hero-inner">
          <div className="hero-row">
            <h1>
              Encuentra tu propiedad <em>ideal</em>
            </h1>
            <p className="hero-lead">Recorre cada espacio en 360° antes de visitarlo e inspírate con renders y planos de creativos.</p>
          </div>
          <SearchForm filters={filters} />
        </div>
      </section>
    <main className="page">
      <IsochroneSearch isochrone={isochrone} properties={isochrone ? onMap : []} otherParams={toQuery({ ...filters, cerca: undefined, tiempo: undefined })} />
      <div className="section-title">
        <div>
          <span className="eyebrow">Propiedades</span>
          <h2>
            Encuentra el lugar <em>para ti</em>
          </h2>
        </div>
        <p className="muted" aria-live="polite">
          {properties.length} {properties.length === 1 ? "propiedad" : "propiedades"}
        </p>
      </div>
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
          {sponsored.map((s) => (
            <PropertyCard key={`ad-${s.adId}`} property={s.property} adId={s.adId} />
          ))}
          {organic.map((p) => (
            <PropertyCard key={p.id} property={p} />
          ))}
        </ul>
      )}
    </main>
    </>
  );
}
