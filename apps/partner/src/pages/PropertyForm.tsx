import { useEffect, useState, type FormEvent } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { PropertyDataSchema, type Property, type PropertyData } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { STATUS_LABEL } from "../lib/properties";
import MediaEditor from "../components/MediaEditor";

/**
 * ZAI-21 · RF-VEN-01 · Alta y edición de una propiedad.
 * ZAI-22 · RF-VEN-02 · Fotos y foto 360 (MediaEditor).
 * El formulario se valida con el mismo esquema Zod que usa todo el proyecto (packages/schemas).
 */
type Errors = Record<string, string>;

const EMPTY: PropertyData = {
  title: "",
  operation: "venta",
  propertyType: "casa",
  price: 0,
  currency: "MXN",
  bedrooms: 0,
  bathrooms: 0,
  location: { state: "", city: "" },
  media: { coverUrl: null, gallery: [], panorama360Url: null },
};

// Convierte el texto de un campo numérico: vacío -> undefined, si no -> número
const num = (v: FormDataEntryValue | null) => (v === null || String(v).trim() === "" ? undefined : Number(v));
const text = (v: FormDataEntryValue | null) => (v === null || String(v).trim() === "" ? undefined : String(v).trim());

export default function PropertyForm() {
  const { id } = useParams();
  const isNew = !id;
  const navigate = useNavigate();
  const { session } = useAuth();
  const [property, setProperty] = useState<Property | null>(null);
  const [initial, setInitial] = useState<PropertyData | null>(isNew ? EMPTY : null);
  const [errors, setErrors] = useState<Errors>({});
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [media, setMedia] = useState<PropertyData["media"]>(EMPTY.media);

  useEffect(() => {
    if (isNew) return;
    supabase
      .from("properties")
      .select("*")
      .eq("id", id)
      .eq("seller_id", session!.user.id)
      .maybeSingle()
      .then(({ data }) => {
        if (!data) return setSaveError("No encontramos esta propiedad o no es tuya.");
        setProperty(data as Property);
        setInitial((data as Property).data);
        setMedia((data as Property).data.media);
      });
  }, [id, isNew, session]);

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setSaveError(null);
    const f = new FormData(e.currentTarget);
    const candidate = {
      title: text(f.get("title")) ?? "",
      description: text(f.get("description")),
      operation: f.get("operation"),
      propertyType: f.get("propertyType"),
      price: num(f.get("price")),
      currency: f.get("currency"),
      bedrooms: num(f.get("bedrooms")) ?? 0,
      bathrooms: num(f.get("bathrooms")) ?? 0,
      areaM2: num(f.get("areaM2")),
      location: {
        state: text(f.get("state")) ?? "",
        city: text(f.get("city")) ?? "",
        neighborhood: text(f.get("neighborhood")),
        address: text(f.get("address")),
        lat: num(f.get("lat")),
        lng: num(f.get("lng")),
      },
      media,
    };
    const parsed = PropertyDataSchema.safeParse(candidate);
    if (!parsed.success) {
      const errs: Errors = {};
      for (const issue of parsed.error.issues) errs[issue.path.join(".")] ??= issue.message;
      setErrors(errs);
      return;
    }
    setErrors({});
    setSaving(true);
    const { error } = isNew
      ? await supabase.from("properties").insert({ seller_id: session!.user.id, status: "draft", data: parsed.data })
      : await supabase.from("properties").update({ data: parsed.data }).eq("id", id);
    setSaving(false);
    if (error) return setSaveError(error.message);
    navigate("/propiedades");
  }

  if (!initial) return <p>{saveError ?? "Cargando…"}</p>;
  const err = (k: string) => errors[k] && <small className="error">{errors[k]}</small>;

  return (
    <section>
      <p>
        <Link to="/propiedades">← Mis propiedades</Link>
      </p>
      <h1>{isNew ? "Nueva propiedad" : `Editar: ${initial.title}`}</h1>
      {property && (
        <p>
          Estado actual: <span className={`badge ${property.status}`}>{STATUS_LABEL[property.status]}</span> (se cambia desde la lista)
        </p>
      )}
      {isNew && <p className="muted">Se guarda como borrador. La publicas desde la lista cuando esté lista.</p>}
      <form onSubmit={onSubmit} className="card form grid" noValidate>
        <label className="span2">
          Título *
          <input name="title" defaultValue={initial.title} maxLength={120} />
          {err("title")}
        </label>
        <label className="span2">
          Descripción
          <textarea name="description" defaultValue={initial.description} rows={4} maxLength={2000} />
          {err("description")}
        </label>
        <label>
          Operación *
          <select name="operation" defaultValue={initial.operation}>
            <option value="venta">Venta</option>
            <option value="renta">Renta</option>
          </select>
        </label>
        <label>
          Tipo *
          <select name="propertyType" defaultValue={initial.propertyType}>
            <option value="casa">Casa</option>
            <option value="departamento">Departamento</option>
            <option value="terreno">Terreno</option>
            <option value="local">Local</option>
            <option value="oficina">Oficina</option>
          </select>
        </label>
        <label>
          Precio *
          <input name="price" type="number" min="1" step="any" defaultValue={initial.price || ""} />
          {err("price")}
        </label>
        <label>
          Moneda
          <select name="currency" defaultValue={initial.currency}>
            <option value="MXN">MXN</option>
            <option value="USD">USD</option>
          </select>
        </label>
        <label>
          Recámaras
          <input name="bedrooms" type="number" min="0" step="1" defaultValue={initial.bedrooms} />
          {err("bedrooms")}
        </label>
        <label>
          Baños
          <input name="bathrooms" type="number" min="0" step="0.5" defaultValue={initial.bathrooms} />
          {err("bathrooms")}
        </label>
        <label>
          Superficie (m²)
          <input name="areaM2" type="number" min="1" step="any" defaultValue={initial.areaM2 ?? ""} />
          {err("areaM2")}
        </label>
        <span />
        <label>
          Estado *
          <input name="state" defaultValue={initial.location.state} placeholder="Jalisco" />
          {err("location.state")}
        </label>
        <label>
          Ciudad *
          <input name="city" defaultValue={initial.location.city} placeholder="Zapopan" />
          {err("location.city")}
        </label>
        <label>
          Colonia
          <input name="neighborhood" defaultValue={initial.location.neighborhood} />
          {err("location.neighborhood")}
        </label>
        <label>
          Dirección
          <input name="address" defaultValue={initial.location.address} />
        </label>
        <label>
          Latitud
          <input name="lat" type="number" step="any" defaultValue={initial.location.lat ?? ""} />
          {err("location.lat")}
        </label>
        <label>
          Longitud
          <input name="lng" type="number" step="any" defaultValue={initial.location.lng ?? ""} />
          {err("location.lng")}
        </label>
        <MediaEditor value={media} onChange={setMedia} />
        {Object.keys(errors).length > 0 && <p className="error span2">Revisa los campos marcados.</p>}
        {saveError && <p className="error span2">{saveError}</p>}
        <div className="span2 row">
          <button className="primary" disabled={saving}>
            {saving ? "Guardando…" : "Guardar"}
          </button>
          <Link to="/propiedades">Cancelar</Link>
        </div>
      </form>
    </section>
  );
}
