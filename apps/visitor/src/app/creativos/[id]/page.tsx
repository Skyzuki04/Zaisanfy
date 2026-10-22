import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SPECIALTY_LABEL } from "@zaisanfy/schemas";
import { getCreativeProfile } from "@/lib/creatives";
import { cld } from "@/lib/cloudinary";
import { SITE_URL } from "@/lib/site";

// ZAI-27 · RF-CRE-01 · Perfil público del creativo.
// ISR: se regenera cada 10 minutos para que los cambios del creativo se vean pronto.
export const revalidate = 600;
export function generateStaticParams() {
  return [];
}

type Props = { params: Promise<{ id: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id } = await params;
  const c = await getCreativeProfile(id);
  if (!c) return { title: "Creativo no encontrado · Zaisanfy", robots: { index: false } };
  const title = `${c.display_name} · ${SPECIALTY_LABEL[c.specialty]}${c.city ? ` en ${c.city}` : ""}`;
  const description = c.bio?.slice(0, 160) ?? `Portafolio de ${c.display_name} en Zaisanfy.`;
  return {
    title: `${title} · Zaisanfy`,
    description,
    alternates: { canonical: `${SITE_URL}/creativos/${c.id}` },
    openGraph: { title, description, type: "profile", images: c.avatar_url ? [cld(c.avatar_url, 600)] : [] },
  };
}

export default async function CreativePage({ params }: Props) {
  const { id } = await params;
  const c = await getCreativeProfile(id);
  if (!c) notFound();

  return (
    <main className="page creative">
      <p>
        <Link href="/">← Propiedades</Link>
      </p>
      <header className="creative-header">
        {c.avatar_url ? (
          <img src={cld(c.avatar_url, 240)} alt={c.display_name} className="creative-avatar" width={120} height={120} />
        ) : (
          <div className="creative-avatar empty" aria-hidden>
            {c.display_name.slice(0, 1).toUpperCase()}
          </div>
        )}
        <div>
          <h1>{c.display_name}</h1>
          <p className="muted">
            {SPECIALTY_LABEL[c.specialty]}
            {c.city ? ` · ${[c.city, c.state].filter(Boolean).join(", ")}` : ""}
          </p>
          {c.website && (
            <a href={c.website} target="_blank" rel="noopener noreferrer nofollow">
              {c.website.replace(/^https?:\/\//, "")}
            </a>
          )}
        </div>
      </header>
      {c.bio && <p className="description">{c.bio}</p>}
    </main>
  );
}
