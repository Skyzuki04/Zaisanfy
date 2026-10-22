import Link from "next/link";
import { notFound } from "next/navigation";
import { getPublishedProperty, orderedPhotos } from "@/lib/properties";
import { formatPrice, TYPE_LABEL } from "@/lib/format";
import Visor360 from "@/components/Visor360";
import Gallery from "@/components/Gallery";

// ZAI-23 · Detalle de la propiedad con su recorrido 360.
export default async function PropertyPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const property = await getPublishedProperty(id);
  if (!property) notFound();
  const d = property.data;
  const photos = orderedPhotos(property);

  return (
    <main className="page detail">
      <p>
        <Link href="/">← Volver a las propiedades</Link>
      </p>
      <h1>{d.title}</h1>
      <p className="muted">
        {TYPE_LABEL[d.propertyType]} en {d.operation} · {[d.location.neighborhood, d.location.city, d.location.state].filter(Boolean).join(", ")}
      </p>
      <p className="price">{formatPrice(d)}{d.operation === "renta" ? " al mes" : ""}</p>

      {d.media.panorama360Url ? (
        <section>
          <h2>Recorrido 360</h2>
          <Visor360 url={d.media.panorama360Url} title={d.title} />
        </section>
      ) : null}

      <section>
        <h2>Fotos</h2>
        <Gallery images={photos} title={d.title} />
      </section>

      <section className="facts card">
        <div><strong>{d.bedrooms}</strong> recámaras</div>
        <div><strong>{d.bathrooms}</strong> baños</div>
        {d.areaM2 && <div><strong>{d.areaM2}</strong> m²</div>}
      </section>
      {d.description && <p className="description">{d.description}</p>}
    </main>
  );
}
