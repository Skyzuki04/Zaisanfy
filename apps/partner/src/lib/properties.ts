import type { Property, PropertyStatus } from "@zaisanfy/schemas";

/** Textos en español de cada estado (RF-VEN-01). */
export const STATUS_LABEL: Record<PropertyStatus, string> = {
  draft: "Borrador",
  published: "Publicada",
  closed: "Cerrada",
  hidden: "Oculta",
};

/** Botón para pasar a cada estado. */
export const STATUS_ACTION: Record<PropertyStatus, string> = {
  draft: "Pasar a borrador",
  published: "Publicar",
  closed: "Marcar como cerrada",
  hidden: "Ocultar",
};

export const ALL_STATUSES: PropertyStatus[] = ["draft", "published", "closed", "hidden"];

export function formatPrice(p: Pick<Property["data"], "price" | "currency">) {
  return new Intl.NumberFormat("es-MX", { style: "currency", currency: p.currency, maximumFractionDigits: 0 }).format(p.price);
}
