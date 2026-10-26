import type { Property } from "@zaisanfy/schemas";

/** Portada primero y después el resto de la galería, sin repetir. */
export function orderedPhotos(p: Property): string[] {
  const { coverUrl, gallery } = p.data.media;
  return coverUrl ? [coverUrl, ...gallery.filter((u) => u !== coverUrl)] : gallery;
}
