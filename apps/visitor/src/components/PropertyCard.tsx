import Link from "next/link";
import type { Property } from "@zaisanfy/schemas";
import { formatPrice, TYPE_LABEL } from "@/lib/format";
import { orderedPhotos } from "@/lib/photos";
import BookmarkButton from "./BookmarkButton";
import { cld } from "@/lib/cloudinary";

/** Tarjeta de una propiedad en los resultados del buscador. */
export default function PropertyCard({ property }: { property: Property }) {
  const d = property.data;
  const cover = orderedPhotos(property)[0];
  return (
    <li className="card property-card">
      <Link href={`/propiedad/${property.id}`} className="cover">
        {cover ? <img src={cld(cover, 640)} alt={d.title} loading="lazy" decoding="async" width={640} height={480} /> : <div className="no-photo">Sin foto</div>}
        {d.media.panorama360Url && <span className="tag360">360°</span>}
      </Link>
      <BookmarkButton propertyId={property.id} title={d.title} className="on-card" />
      <h2>
        <Link href={`/propiedad/${property.id}`}>{d.title}</Link>
      </h2>
      <p className="muted">
        {TYPE_LABEL[d.propertyType]} en {d.operation} · {d.location.city}, {d.location.state}
      </p>
      <p className="price">
        {formatPrice(d)}
        {d.operation === "renta" ? " al mes" : ""}
      </p>
    </li>
  );
}
