import type { Metadata } from "next";
import Link from "next/link";
import ContactRequest from "@/components/ContactRequest";
import { notFound } from "next/navigation";
import { getPublishedProperty, orderedPhotos } from "@/lib/properties";
import { formatPrice, TYPE_LABEL } from "@/lib/format";
import Visor360 from "@/components/Visor360";
import Gallery from "@/components/Gallery";
import PostCard from "@/components/PostCard";
import BookmarkButton from "@/components/BookmarkButton";
import { getSuggestedPosts } from "@/lib/suggestions";
import { cld } from "@/lib/cloudinary";
import { jsonLdString, propertyDescription, propertyJsonLd, propertyTitle, propertyUrl } from "@/lib/seo";

type Props = { params: Promise<{ id: string }> };

export const revalidate = 3600;
export const dynamicParams = true;
export function generateStaticParams() {
  return [];
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;
  const property = await getPublishedProperty(id);
  if (!property) return { title: "Propiedad no disponible · Zaisanfy", robots: { index: false } };
  const title = propertyTitle(property);
  const description = propertyDescription(property);
  const images = orderedPhotos(property).slice(0, 1).map((u) => cld(u, 1200));
  return {
    title: `${title} · Zaisanfy`,
    description,
    alternates: { canonical: propertyUrl(property.id) },
    openGraph: { title, description, url: propertyUrl(property.id), type: "website", locale: "es_MX", siteName: "Zaisanfy", images },
    twitter: { card: images.length ? "summary_large_image" : "summary", title, description, images },
  };
}

export default async function PropertyPage({ params }: Props) {
  const { id } = await params;
  const property = await getPublishedProperty(id);
  if (!property) notFound();
  const d = property.data;
  const photos = orderedPhotos(property);
  const suggestions = await getSuggestedPosts(property);

  return (
    <main className="page detail">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdString(propertyJsonLd(property)) }} />
      <p>
        <Link href="/">← Volver a las propiedades</Link>
      </p>
      <div className="title-row">
        <h1>{d.title}</h1>
        <BookmarkButton propertyId={property.id} title={d.title} />
      </div>
      <p className="muted">
        {TYPE_LABEL[d.propertyType]} en {d.operation} · {[d.location.neighborhood, d.location.city, d.location.state].filter(Boolean).join(", ")}
      </p>
      <p className="price">{formatPrice(d)}{d.operation === "renta" ? " al mes" : ""}</p>
      <ContactRequest kind="visita" ownerId={property.seller_id} propertyId={property.id} operation={d.operation} label="Contactar al vendedor · Agendar visita" />

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

      {suggestions.length > 0 && (
        <section className="inspiration" aria-labelledby="inspiracion">
          <div className="section-head">
            <h2 id="inspiracion">Inspiración</h2>
            <Link href="/muro">Ver más en el muro →</Link>
          </div>
          <p className="muted">Renders, planos e ideas de creativos para propiedades como esta.</p>
          <ul className="cards posts">
            {suggestions.map((p) => (
              <PostCard key={p.id} post={p} />
            ))}
          </ul>
        </section>
      )}
    </main>
  );
}
