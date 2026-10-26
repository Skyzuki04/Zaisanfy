import { useEffect, useState, type ChangeEvent, type FormEvent } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  CATEGORY_LABEL,
  CreativePostInputSchema,
  MAX_POST_IMAGES,
  PropertyType,
  type CreativePost,
} from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { checkImage, uploadImage } from "../lib/cloudinary";

/**
 * ZAI-28 · RF-CRE-01 · Crear o editar una publicación del portafolio.
 * Las imágenes suben directo a Cloudinary; en creative_posts solo se guardan las URLs.
 * La primera imagen es la portada.
 */
type Pending = { id: string; name: string; preview: string };

const TYPE_LABEL: Record<PropertyType, string> = {
  casa: "Casa",
  departamento: "Departamento",
  terreno: "Terreno",
  local: "Local",
  oficina: "Oficina",
};
const blank = (v: FormDataEntryValue | null) => (v === null || String(v).trim() === "" ? null : String(v).trim());

export default function PostForm() {
  const { id } = useParams();
  const isNew = !id;
  const navigate = useNavigate();
  const { session } = useAuth();
  const [post, setPost] = useState<CreativePost | null | undefined>(isNew ? null : undefined);
  const [images, setImages] = useState<string[]>([]);
  const [pending, setPending] = useState<Pending[]>([]);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [uploadErrors, setUploadErrors] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (isNew) return;
    supabase
      .from("creative_posts")
      .select("*")
      .eq("id", id)
      .maybeSingle()
      .then(({ data }) => {
        setPost((data as CreativePost) ?? null);
        setImages((data as CreativePost | null)?.images ?? []);
      });
  }, [id, isNew]);

  async function onFiles(e: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    e.target.value = "";
    const errs: string[] = [];
    const room = MAX_POST_IMAGES - images.length - pending.length;
    if (files.length > room) errs.push(`Máximo ${MAX_POST_IMAGES} imágenes. Solo se subirán ${Math.max(room, 0)}.`);

    const accepted: { file: File; p: Pending }[] = [];
    for (const file of files.slice(0, Math.max(room, 0))) {
      const err = await checkImage(file);
      if (err) errs.push(err);
      else accepted.push({ file, p: { id: crypto.randomUUID(), name: file.name, preview: URL.createObjectURL(file) } });
    }
    setUploadErrors(errs);
    setPending((prev) => [...prev, ...accepted.map((a) => a.p)]);

    for (const { file, p } of accepted) {
      try {
        const url = await uploadImage(file);
        setImages((prev) => [...prev, url]);
      } catch (err) {
        setUploadErrors((prev) => [...prev, `${p.name}: ${(err as Error).message}`]);
      } finally {
        setPending((prev) => prev.filter((x) => x.id !== p.id));
        URL.revokeObjectURL(p.preview);
      }
    }
  }

  function move(i: number, dir: -1 | 1) {
    const j = i + dir;
    if (j < 0 || j >= images.length) return;
    const next = [...images];
    [next[i], next[j]] = [next[j], next[i]];
    setImages(next);
  }

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    const parsed = CreativePostInputSchema.safeParse({
      title: f.get("title") ?? "",
      description: blank(f.get("description")),
      category: f.get("category"),
      images,
      property_type: blank(f.get("property_type")),
      city: blank(f.get("city")),
    });
    if (!parsed.success) {
      const errs: Record<string, string> = {};
      for (const i of parsed.error.issues) errs[String(i.path[0])] ??= i.message;
      return setErrors(errs);
    }
    setErrors({});
    setSaving(true);
    const { error } = isNew
      ? await supabase.from("creative_posts").insert({ creative_id: session!.user.id, ...parsed.data })
      : await supabase.from("creative_posts").update(parsed.data).eq("id", id);
    setSaving(false);
    if (error) return setErrors({ form: error.message });
    navigate("/portafolio");
  }

  if (post === undefined) return <p>Cargando…</p>;
  // RLS ya impide guardar cambios ajenos; aquí solo se evita mostrar el formulario
  if (!isNew && (post === null || post.creative_id !== session!.user.id)) {
    return <p className="card">Esta publicación no existe o no es tuya.</p>;
  }
  const err = (k: string) => errors[k] && <small className="error">{errors[k]}</small>;

  return (
    <section>
      <h1>{isNew ? "Nueva publicación" : "Editar publicación"}</h1>
      <form onSubmit={onSubmit} className="card form grid" noValidate>
        <label>
          Título *
          <input name="title" defaultValue={post?.title ?? ""} maxLength={120} />
          {err("title")}
        </label>
        <label>
          Categoría *
          <select name="category" defaultValue={post?.category ?? "render"}>
            {Object.entries(CATEGORY_LABEL).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
          {err("category")}
        </label>
        <label className="span2">
          Descripción
          <textarea name="description" rows={4} maxLength={2000} defaultValue={post?.description ?? ""} />
          {err("description")}
        </label>
        <p className="span2 muted">
          Opcional: si indicas el tipo de propiedad o la ciudad, tu diseño se sugiere en propiedades parecidas.
        </p>
        <label>
          Tipo de propiedad
          <select name="property_type" defaultValue={post?.property_type ?? ""}>
            <option value="">Cualquiera</option>
            {PropertyType.options.map((t) => (
              <option key={t} value={t}>
                {TYPE_LABEL[t]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Ciudad
          <input name="city" defaultValue={post?.city ?? ""} maxLength={80} />
          {err("city")}
        </label>

        <div className="media span2">
          <h2>Imágenes *</h2>
          <p className="muted">
            De 1 a {MAX_POST_IMAGES} imágenes (JPG, PNG o WebP de hasta 10 MB). La primera es la portada.
          </p>
          <label className="button">
            + Agregar imágenes
            <input type="file" accept="image/*" multiple onChange={onFiles} hidden data-testid="post-images" />
          </label>
          {err("images")}
          {uploadErrors.map((m) => (
            <p key={m} className="error">
              {m}
            </p>
          ))}
          <ul className="thumbs">
            {images.map((url, i) => (
              <li key={url} className={i === 0 ? "cover" : ""}>
                <img src={url} alt={`Imagen ${i + 1}`} />
                {i === 0 && <span className="badge published">Portada</span>}
                <div className="row">
                  <button type="button" className="small" onClick={() => move(i, -1)} disabled={i === 0} aria-label="Mover a la izquierda">
                    ←
                  </button>
                  <button type="button" className="small" onClick={() => move(i, 1)} disabled={i === images.length - 1} aria-label="Mover a la derecha">
                    →
                  </button>
                  <button type="button" className="small danger" onClick={() => setImages(images.filter((u) => u !== url))}>
                    Quitar
                  </button>
                </div>
              </li>
            ))}
            {pending.map((p) => (
              <li key={p.id} className="uploading">
                <img src={p.preview} alt={p.name} />
                <span className="muted">Subiendo…</span>
              </li>
            ))}
          </ul>
        </div>

        {errors.form && <p className="span2 error">{errors.form}</p>}
        <div className="span2 row">
          <button className="primary" disabled={saving || pending.length > 0}>
            {saving ? "Guardando…" : "Guardar publicación"}
          </button>
          <button type="button" onClick={() => navigate("/portafolio")}>
            Cancelar
          </button>
        </div>
      </form>
    </section>
  );
}
