import { useCallback, useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { CATEGORY_LABEL, type CreativePost } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { withSession } from "../components/Layout";

const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";

export default function MiPortafolio() {
  const { session } = useAuth();
  const userId = session!.user.id;
  const [hasProfile, setHasProfile] = useState<boolean | null>(null);
  const [rows, setRows] = useState<CreativePost[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const location = useLocation();
  const [notice, setNotice] = useState<string | null>((location.state as { notice?: string } | null)?.notice ?? null);

  const load = useCallback(async () => {
    const [{ data: prof }, { data, error }] = await Promise.all([
      supabase.from("creative_profiles").select("id").eq("id", userId).maybeSingle(),
      supabase.from("creative_posts").select("*").eq("creative_id", userId).order("created_at", { ascending: false }),
    ]);
    setHasProfile(!!prof);
    if (error) setError(error.message);
    setRows((data as CreativePost[]) ?? []);
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);

  async function remove(p: CreativePost) {
    if (!window.confirm(`¿Borrar "${p.title}"? No se puede deshacer.`)) return;
    const { error } = await supabase.from("creative_posts").delete().eq("id", p.id);
    if (error) setError(error.message);
    else setNotice(`Se borró “${p.title}”.`);
    load();
  }

  if (hasProfile === null) return <p>Cargando…</p>;
  if (!hasProfile) {
    return (
      <div className="card">
        <h2>Primero llena tu perfil</h2>
        <p>Tu portafolio se muestra en tu perfil público, así que necesitas crearlo antes de publicar.</p>
        <Link to="/perfil" className="button primary">
          Ir a Mi perfil
        </Link>
      </div>
    );
  }

  return (
    <section>
      <div className="row between">
        <h1>Mi portafolio</h1>
        <div className="row">
          <a href={`${visitorUrl}/creativos/${userId}`} target="_blank" rel="noreferrer" onClick={(e) => withSession(e, session)} className="button">
            Ver en mi perfil
          </a>
          <Link to="/portafolio/nueva" className="button primary">
            + Nueva publicación
          </Link>
        </div>
      </div>
      {error && <p className="error">{error}</p>}
      {notice && (
        <p className="flash" role="status">
          {notice}
          <button type="button" className="link" onClick={() => setNotice(null)} aria-label="Cerrar aviso">
            ✕
          </button>
        </p>
      )}
      {rows?.length === 0 && (
        <div className="card empty-state">
          <h2>
            Todavía no tienes <em>publicaciones</em>
          </h2>
          <p className="muted">Sube tu primer render, plano o idea. Aparecerá en tu perfil público y en el muro de inspiración.</p>
          <Link to="/portafolio/nueva" className="button primary">
            + Subir mi primer trabajo
          </Link>
        </div>
      )}
      {rows && rows.length > 0 && (
        <ul className="posts">
          {rows.map((p) => (
            <li key={p.id} className="card">
              <img src={p.images[0]} alt={p.title} />
              <span className="badge">{CATEGORY_LABEL[p.category]}</span>
              <strong>{p.title}</strong>
              <span className="muted">
                {p.images.length} {p.images.length === 1 ? "imagen" : "imágenes"}
              </span>
              <div className="row">
                <Link to={`/portafolio/${p.id}`} className="button small">
                  Editar
                </Link>
                <button className="small danger" onClick={() => remove(p)}>
                  Borrar
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
