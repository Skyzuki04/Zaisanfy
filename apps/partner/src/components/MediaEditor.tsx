import { useState, type ChangeEvent } from "react";
import type { PropertyData } from "@zaisanfy/schemas";
import { check360, checkImage, uploadImage } from "../lib/cloudinary";

/**
 * ZAI-22 · RF-VEN-02 · Fotos normales y foto 360 de una propiedad.
 * - Varias fotos a la vez, con vista previa mientras suben.
 * - Portada y orden de la galería.
 * - La foto 360 se valida (2:1) antes de subirla.
 */
type Media = PropertyData["media"];
type Pending = { id: string; name: string; preview: string };

const MAX_GALLERY = 30;

export default function MediaEditor({ value, onChange }: { value: Media; onChange: (m: Media) => void }) {
  const [pending, setPending] = useState<Pending[]>([]);
  const [pending360, setPending360] = useState<string | null>(null);
  const [errors, setErrors] = useState<string[]>([]);

  async function onPhotos(e: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? []);
    e.target.value = "";
    const errs: string[] = [];
    const room = MAX_GALLERY - value.gallery.length;
    if (files.length > room) errs.push(`Máximo ${MAX_GALLERY} fotos. Solo se subirán ${Math.max(room, 0)}.`);

    const accepted: { file: File; p: Pending }[] = [];
    for (const file of files.slice(0, Math.max(room, 0))) {
      const err = await checkImage(file);
      if (err) errs.push(err);
      else accepted.push({ file, p: { id: crypto.randomUUID(), name: file.name, preview: URL.createObjectURL(file) } });
    }
    setErrors(errs);
    setPending((prev) => [...prev, ...accepted.map((a) => a.p)]);

    let media = value;
    for (const { file, p } of accepted) {
      try {
        const url = await uploadImage(file);
        media = { ...media, gallery: [...media.gallery, url], coverUrl: media.coverUrl ?? url };
        onChange(media);
      } catch (err) {
        setErrors((prev) => [...prev, `${p.name}: ${(err as Error).message}`]);
      } finally {
        setPending((prev) => prev.filter((x) => x.id !== p.id));
        URL.revokeObjectURL(p.preview);
      }
    }
  }

  async function on360(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    const err = await check360(file);
    if (err) return setErrors([err]);
    setErrors([]);
    const preview = URL.createObjectURL(file);
    setPending360(preview);
    try {
      const url = await uploadImage(file);
      onChange({ ...value, panorama360Url: url });
    } catch (e) {
      setErrors([`Foto 360: ${(e as Error).message}`]);
    } finally {
      setPending360(null);
      URL.revokeObjectURL(preview);
    }
  }

  function move(i: number, dir: -1 | 1) {
    const g = [...value.gallery];
    const j = i + dir;
    if (j < 0 || j >= g.length) return;
    [g[i], g[j]] = [g[j], g[i]];
    onChange({ ...value, gallery: g });
  }

  function remove(url: string) {
    const gallery = value.gallery.filter((u) => u !== url);
    onChange({ ...value, gallery, coverUrl: value.coverUrl === url ? (gallery[0] ?? null) : value.coverUrl });
  }

  return (
    <div className="media span2">
      <h2>Fotos</h2>
      <p className="muted">JPG, PNG o WebP de hasta 10 MB. La portada es la que se ve primero en el buscador.</p>
      <label className="button">
        + Agregar fotos
        <input type="file" accept="image/*" multiple onChange={onPhotos} hidden data-testid="photos" />
      </label>
      <ul className="thumbs">
        {value.gallery.map((url, i) => (
          <li key={url} className={value.coverUrl === url ? "cover" : ""}>
            <img src={url} alt={`Foto ${i + 1}`} />
            {value.coverUrl === url ? (
              <span className="badge published">Portada</span>
            ) : (
              <button type="button" className="small" onClick={() => onChange({ ...value, coverUrl: url })}>
                Usar como portada
              </button>
            )}
            <div className="row">
              <button type="button" className="small" onClick={() => move(i, -1)} disabled={i === 0} aria-label="Mover a la izquierda">
                ←
              </button>
              <button type="button" className="small" onClick={() => move(i, 1)} disabled={i === value.gallery.length - 1} aria-label="Mover a la derecha">
                →
              </button>
              <button type="button" className="small danger" onClick={() => remove(url)}>
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

      <h2>Foto 360</h2>
      <p className="muted">Imagen equirectangular 2:1 (por ejemplo 6000 × 3000), de hasta 10 MB y 25 megapíxeles.</p>
      <div className="row">
        <label className="button">
          {value.panorama360Url ? "Cambiar foto 360" : "+ Subir foto 360"}
          <input type="file" accept="image/*" onChange={on360} hidden data-testid="pano" />
        </label>
        {value.panorama360Url && (
          <button type="button" className="small danger" onClick={() => onChange({ ...value, panorama360Url: null })}>
            Quitar 360
          </button>
        )}
      </div>
      {(pending360 || value.panorama360Url) && (
        <div className="pano">
          <img src={pending360 ?? value.panorama360Url!} alt="Foto 360" />
          {pending360 && <span className="muted">Subiendo…</span>}
        </div>
      )}
      {errors.map((e) => (
        <p key={e} className="error">
          {e}
        </p>
      ))}
    </div>
  );
}
