import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CATEGORY_LABEL } from "@zaisanfy/schemas";
import { getPost } from "@/lib/posts";
import { TYPE_LABEL } from "@/lib/format";
import { cld } from "@/lib/cloudinary";
import { jsonLdString, postDescription, postJsonLd, postUrl } from "@/lib/seo";
import Gallery from "@/components/Gallery";

// ZAI-28 · Página de un render, plano o idea, con JSON-LD VisualArtwork (RNF-SEO-01).
export const revalidate = 600;
export function generateStaticParams() {
  return [];
}

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;
  const p = await getPost(id);
  if (!p) return { title: "Publicación no encontrada · Zaisanfy", robots: { index: false } };
  const title = `${p.title} · ${CATEGORY_LABEL[p.category]} de ${p.creative.display_name}`;
  const description = postDescription(p);
  const images = [cld(p.images[0], 1200)];
  return {
    title: `${title} · Zaisanfy`,
    description,
    alternates: { canonical: postUrl(p.id) },
    openGraph: { title, description, url: postUrl(p.id), type: "article", locale: "es_MX", siteName: "Zaisanfy", images },
    twitter: { card: "summary_large_image", title, description, images },
  };
}

export default async function PostPage({ params }: Props) {
  const { id } = await params;
  const p = await getPost(id);
  if (!p) notFound();

  return (
    <main className="page detail">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdString(postJsonLd(p)) }} />
      <p>
        <Link href={`/creativos/${p.creative.id}`}>← Portafolio de {p.creative.display_name}</Link>
      </p>
      <h1>{p.title}</h1>
      <p className="muted">
        {CATEGORY_LABEL[p.category]} por <Link href={`/creativos/${p.creative.id}`}>{p.creative.display_name}</Link>
        {p.property_type ? ` · ${TYPE_LABEL[p.property_type]}` : ""}
        {p.city ? ` · ${p.city}` : ""}
      </p>
      <Gallery images={p.images} title={p.title} />
      {p.description && <p className="description">{p.description}</p>}
    </main>
  );
}
