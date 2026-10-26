import { useEffect, useState, type ChangeEvent, type FormEvent } from "react";
import { CreativeProfileInputSchema, SPECIALTY_LABEL, type CreativeProfile } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { checkImage, uploadImage } from "../lib/cloudinary";

/**
 * ZAI-27 · RF-CRE-01 · "Mi perfil" del creativo.
 * Crea o edita su fila en creative_profiles (RLS: solo el dueño con rol creativo).
 */
const visitorUrl = import.meta.env.VITE_VISITOR_URL ?? "http://localhost:3000";
const blank = (v: FormDataEntryValue | null) => (v === null || String(v).trim() === "" ? null : String(v).trim());

export default function MiPerfil() {
  const { session, profile } = useAuth();
  const userId = session!.user.id;
  const [current, setCurrent] = useState<CreativeProfile | null | undefined>(undefined);
  const [avatar, setAvatar] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    supabase
      .from("creative_profiles")
      .select("*")
      .eq("id", userId)
      .maybeSingle()
      .then(({ data }) => {
        setCurrent((data as CreativeProfile) ?? null);
        setAvatar((data as CreativeProfile | null)?.avatar_url ?? null);
      });
  }, [userId]);

  async function onAvatar(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    const err = await checkImage(file);
    if (err) return setMessage({ ok: false, text: err });
    setUploading(true);
    try {
      setAvatar(await uploadImage(file));
    } catch (e) {
      setMessage({ ok: false, text: (e as Error).message });
    } finally {
      setUploading(false);
    }
  }

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setMessage(null);
    const f = new FormData(e.currentTarget);
    const parsed = CreativeProfileInputSchema.safeParse({
      display_name: f.get("display_name") ?? "",
      specialty: f.get("specialty"),
      bio: blank(f.get("bio")),
      city: blank(f.get("city")),
      state: blank(f.get("state")),
      website: blank(f.get("website")),
      avatar_url: avatar,
    });
    if (!parsed.success) {
      const errs: Record<string, string> = {};
      for (const i of parsed.error.issues) errs[i.path.join(".")] ??= i.message;
      return setErrors(errs);
    }
    setErrors({});
    const { data, error } = await supabase
      .from("creative_profiles")
      .upsert({ id: userId, ...parsed.data })
      .select()
      .single();
    if (error) return setMessage({ ok: false, text: error.message });
    setCurrent(data as CreativeProfile);
    setMessage({ ok: true, text: "Perfil guardado" });
  }

  if (current === undefined) return <p>Cargando…</p>;
  const err = (k: string) => errors[k] && <small className="error">{errors[k]}</small>;

  return (
    <section>
      <div className="row between">
        <h1>Mi perfil</h1>
        {current && (
          <a href={`${visitorUrl}/creativos/${userId}`} target="_blank" rel="noreferrer" className="button">
            Ver mi perfil público
          </a>
        )}
      </div>
      {!current && <p className="muted">Todavía no tienes perfil público. Llénalo para aparecer en Zaisanfy.</p>}
      <form onSubmit={onSubmit} className="card form grid" noValidate>
        <div className="span2 row">
          {avatar ? <img src={avatar} alt="Tu foto" className="avatar" /> : <div className="avatar empty">Sin foto</div>}
          <label className="button">
            {uploading ? "Subiendo…" : avatar ? "Cambiar foto" : "Subir foto"}
            <input type="file" accept="image/*" onChange={onAvatar} hidden data-testid="avatar" />
          </label>
          {avatar && (
            <button type="button" className="small danger" onClick={() => setAvatar(null)}>
              Quitar foto
            </button>
          )}
        </div>
        <label>
          Nombre o estudio *
          <input name="display_name" defaultValue={current?.display_name ?? profile?.full_name ?? ""} maxLength={80} />
          {err("display_name")}
        </label>
        <label>
          Especialidad
          <select name="specialty" defaultValue={current?.specialty ?? "render3d"}>
            {Object.entries(SPECIALTY_LABEL).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </label>
        <label className="span2">
          Sobre mí
          <textarea name="bio" rows={4} maxLength={1000} defaultValue={current?.bio ?? ""} />
          {err("bio")}
        </label>
        <label>
          Ciudad
          <input name="city" defaultValue={current?.city ?? ""} />
          {err("city")}
        </label>
        <label>
          Estado
          <input name="state" defaultValue={current?.state ?? ""} />
          {err("state")}
        </label>
        <label className="span2">
          Sitio web o portafolio externo
          <input name="website" type="url" placeholder="https://" defaultValue={current?.website ?? ""} />
          {err("website")}
        </label>
        {message && <p className={`span2 ${message.ok ? "notice" : "error"}`}>{message.text}</p>}
        <div className="span2">
          <button className="primary" disabled={uploading}>
            Guardar perfil
          </button>
        </div>
      </form>
    </section>
  );
}
