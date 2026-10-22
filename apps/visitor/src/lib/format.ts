import type { PropertyData } from "@zaisanfy/schemas";

export function formatPrice(p: Pick<PropertyData, "price" | "currency">) {
  return new Intl.NumberFormat("es-MX", { style: "currency", currency: p.currency, maximumFractionDigits: 0 }).format(p.price);
}

export const TYPE_LABEL: Record<PropertyData["propertyType"], string> = {
  casa: "Casa",
  departamento: "Departamento",
  terreno: "Terreno",
  local: "Local",
  oficina: "Oficina",
};
