import Link from "next/link";
import { CATEGORY_LABEL } from "@zaisanfy/schemas";
import type { PostWithCreative } from "@/lib/posts";
import { cld } from "@/lib/cloudinary";

/** Tarjeta de un render, plano o idea. En el muro muestra quién lo subió con enlace a su perfil. */
export default function PostCard({ post, showCreative = true }: { post: PostWithCreative; showCreative?: boolean }) {
  return (
    <li className="card post-card">
      <Link href={`/publicaciones/${post.id}`} className="cover">
        <img src={cld(post.images[0], 640)} alt={post.title} loading="lazy" decoding="async" width={640} height={480} />
        <span className="tag-category">{CATEGORY_LABEL[post.category]}</span>
      </Link>
      <h3>
        <Link href={`/publicaciones/${post.id}`}>{post.title}</Link>
      </h3>
      {showCreative && post.creative && (
        <p className="muted">
          por <Link href={`/creativos/${post.creative.id}`}>{post.creative.display_name}</Link>
        </p>
      )}
    </li>
  );
}
