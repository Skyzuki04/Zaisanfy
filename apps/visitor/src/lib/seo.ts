import type { Property } from "@zaisanfy/schemas";
import { SITE_URL } from "./site";
import { TYPE_LABEL } from "./format";
import { orderedPhotos } from "./properties";
import { cld } from "./cloudinary";

/**
 * ZAI-25 · RNF-SEO-01 · Datos estructurados (Schema.org) de una propiedad.
 * RealEstateListing describe el anuncio; la propiedad va en "about" con su dirección y medidas.
 */
const RESIDENCE_TYPE: Record<Property["data"]["propertyType"], string> = {
  casa: "SingleFamilyResidence",
  departamento: "Apartment",
  terreno: "Place",
  local: "Place",
  oficina: "Place",
};

export function propertyUrl(id: string) {
  return `${SITE_URL}/propiedad/${id}`;
}

export function propertyTitle(p: Property) {
  const d = p.data;
  return `${d.title} · ${TYPE_LABEL[d.propertyType]} en ${d.operation} en ${d.location.city}`;
}

export function propertyDescription(p: Property) {
  const d = p.data;
  if (d.description) return d.description.slice(0, 160);
  const parts = [
    `${TYPE_LABEL[d.propertyType]} en ${d.operation} en ${d.location.city}, ${d.location.state}`,
    d.bedrooms ? `${d.bedrooms} recámaras` : null,
    d.areaM2 ? `${d.areaM2} m²` : null,
    d.media.panorama360Url ? "con recorrido 360" : null,
  ];
  return parts.filter(Boolean).join(" · ") + ".";
}

export function propertyJsonLd(p: Property) {
  const d = p.data;
  const url = propertyUrl(p.id);
  const residence: Record<string, unknown> = {
    "@type": RESIDENCE_TYPE[d.propertyType],
    name: d.title,
    address: {
      "@type": "PostalAddress",
      streetAddress: d.location.address,
      addressLocality: d.location.city,
      addressRegion: d.location.state,
      addressCountry: "MX",
    },
  };
  if (d.location.lat !== undefined && d.location.lng !== undefined) {
    residence.geo = { "@type": "GeoCoordinates", latitude: d.location.lat, longitude: d.location.lng };
  }
  if (d.propertyType === "casa" || d.propertyType === "departamento") {
    residence.numberOfBedrooms = d.bedrooms;
    residence.numberOfBathroomsTotal = d.bathrooms;
  }
  if (d.areaM2) {
    // floorSize solo existe en viviendas (Accommodation); en Place la superficie va como additionalProperty
    if (residence["@type"] === "Place") {
      residence.additionalProperty = { "@type": "PropertyValue", name: "Superficie", value: d.areaM2, unitCode: "MTK" };
    } else {
      residence.floorSize = { "@type": "QuantitativeValue", value: d.areaM2, unitCode: "MTK" };
    }
  }

  return [
    {
      "@context": "https://schema.org",
      "@type": "RealEstateListing",
      name: d.title,
      description: propertyDescription(p),
      url,
      image: orderedPhotos(p).map((u) => cld(u, 1200)),
      datePosted: p.created_at,
      dateModified: p.updated_at,
      offers: {
        "@type": "Offer",
        price: d.price,
        priceCurrency: d.currency,
        businessFunction: d.operation === "renta" ? "http://purl.org/goodrelations/v1#LeaseOut" : "http://purl.org/goodrelations/v1#Sell",
        availability: "https://schema.org/InStock",
        url,
      },
      about: residence,
    },
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      itemListElement: [
        { "@type": "ListItem", position: 1, name: "Propiedades", item: `${SITE_URL}/` },
        { "@type": "ListItem", position: 2, name: d.location.city, item: `${SITE_URL}/?ubicacion=${encodeURIComponent(d.location.city)}` },
        { "@type": "ListItem", position: 3, name: d.title, item: url },
      ],
    },
  ];
}

/** JSON seguro para <script type="application/ld+json"> (evita cerrar la etiqueta con "</script>"). */
export function jsonLdString(data: unknown) {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
