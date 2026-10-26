import type { Metadata } from "next";
import Link from "next/link";
import { CATEGORY_LABEL, PostCategory } from "@zaisanfy/schemas";
import PostCard from "@/components/PostCard";
import { getWall, parseWallFilters, WALL_PAGE_SIZE, type WallFilters } from "@/lib/posts";
import { SITE_URL } from "@/lib/site";

// ZAI-29 · FEED-01 · Muro de inspiración: renders, planos e ideas de los creativos.
export const metadata: Metadata = {
  title: "Muro de inspiración · Zaisanfy",
  description: "Renders, planos e ideas de arquitectos y creativos para inspirar tu próxima casa.",
  alternates: { canonical: `${SITE_URL}/muro` },
};

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

/** Arma el enlace conservando el filtro (los filtros viven en la URL). */
function wallHref({ page, category }: WallFilters) {
  const sp = new URLSearchParams();
  if (category) sp.set("categoria", category);
  if (page > 1) sp.set("page", String(page));
  const qs = sp.toString();
  return qs ? `/muro?${qs}` : "/muro";
}

export default async function Muro({ searchParams }: Props) {
  const filters = parseWallFilters(await searchParams);
  const { posts, total } = await getWall(filters);
  const pages = Math.max(1, Math.ceil(total / WALL_PAGE_SIZE));

  return (
    <main className="page">
      <h1>Muro de inspiración</h1>
      <nav className="chips" aria-label="Filtrar por categoría">
        <Link href={wallHref({ page: 1, category: null })} className={!filters.category ? "chip active" : "chip"} aria-current={!filters.category ? "page" : undefined}>
          Todo
        </Link>
        {PostCategory.options.map((c) => (
          <Link key={c} href={wallHref({ page: 1, category: c })} className={filters.category === c ? "chip active" : "chip"} aria-current={filters.category === c ? "page" : undefined}>
            {CATEGORY_LABEL[c]}
          </Link>
        ))}
      </nav>

      {posts.length === 0 ? (
        <div className="card empty">
          <h2>Sin publicaciones</h2>
          <p>{filters.category || filters.page > 1 ? "No hay publicaciones aquí." : "Los creativos todavía no han publicado."}</p>
          {(filters.category || filters.page > 1) && (
            <Link href="/muro" className="button">
              Ver todo el muro
            </Link>
          )}
        </div>
      ) : (
        <ul className="cards posts">
          {posts.map((p) => (
            <PostCard key={p.id} post={p} />
          ))}
        </ul>
      )}

      {pages > 1 && (
        <nav className="pager" aria-label="Páginas">
          {filters.page > 1 ? <Link href={wallHref({ ...filters, page: filters.page - 1 })} rel="prev">← Anteriores</Link> : <span />}
          <span className="muted">
            Página {Math.min(filters.page, pages)} de {pages}
          </span>
          {filters.page < pages ? <Link href={wallHref({ ...filters, page: filters.page + 1 })} rel="next">Siguientes →</Link> : <span />}
        </nav>
      )}
    </main>
  );
}
