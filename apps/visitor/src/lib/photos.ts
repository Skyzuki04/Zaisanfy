import type { Property } from "@zaisanfy/schemas";

export function orderedPhotos(p: Property): string[] {
  const { coverUrl, gallery } = p.data.media;
  return coverUrl ? [coverUrl, ...gallery.filter((u) => u !== coverUrl)] : gallery;
}
