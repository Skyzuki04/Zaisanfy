import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import Loading from "../components/Loading";
import { Link } from "react-router-dom";
import { friendlyError } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";

// ZAI-39 · SRV-01: fotógrafo 360 a domicilio. El vendedor pide; los fotógrafos cercanos aceptan.
// Los cambios llegan en vivo con Supabase Realtime (migración 0017).
type Status = "pedido" | "aceptado" | "en_camino" | "terminado" | "cancelado";
type Service = {
  id: string;
  property_id: string;
  scheduled_at: string;
  address: string;
  notes: string | null;
  status: Status;
  accepted_at: string | null;
  finished_at: string | null;
  property: { title: string } | null;
  photographer: { display_name: string } | null;
};
type Nearby = { id: string; property_title: string; city: string; neighborhood: string | null; scheduled_at: string; notes: string | null; distance_km: number };

const STEPS: Status[] = ["pedido", "aceptado", "en_camino", "terminado"];
const STATUS_LABEL: Record<Status, string> = { pedido: "Pedido", aceptado: "Aceptado", en_camino: "En camino", terminado: "Terminado", cancelado: "Cancelado" };
const dateFmt = new Intl.DateTimeFormat("es-MX", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const SELECT = "id, property_id, scheduled_at, address, notes, status, accepted_at, finished_at, property:properties(title), photographer:creative_profiles(display_name)";

function Timeline({ status }: { status: Status }) {
  if (status === "cancelado") return <span className="badge hidden">Cancelado</span>;
  const at = STEPS.indexOf(status);
  return (
    <ol className="timeline" aria-label={`Estado: ${STATUS_LABEL[status]}`}>
      {STEPS.map((s, i) => (
        <li key={s} className={i < at ? "done" : i === at ? "now" : ""}>
          {STATUS_LABEL[s]}
        </li>
      ))}
    </ol>
  );
}

/** Recarga cuando cambia algo en service_requests (Realtime respeta RLS: cada quien recibe solo lo suyo). */
function useLive(reload: () => void) {
  useEffect(() => {
    const ch = supabase
      .channel("service_requests")
      .on("postgres_changes", { event: "*", schema: "public", table: "service_requests" }, () => reload())
      .subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [reload]);
}

function SellerView({ userId }: { userId: string }) {
  const [props, setProps] = useState<{ id: string; title: string; lat: number | null }[]>([]);
  const [rows, setRows] = useState<Service[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [p, s] = await Promise.all([
      supabase.from("properties").select("id, title, lat").eq("seller_id", userId).neq("status", "closed").order("title"),
      supabase.from("service_requests").select(SELECT).eq("seller_id", userId).order("created_at", { ascending: false }),
    ]);
    if (s.error) setError(friendlyError(s.error));
    setProps((p.data as { id: string; title: string; lat: number | null }[]) ?? []);
    setRows((s.data as unknown as Service[]) ?? []);
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);
  useLive(load);

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setNotice(null);
    const f = new FormData(e.currentTarget);
    const propertyId = String(f.get("property") ?? "");
    const when = String(f.get("when") ?? "");
    if (!propertyId) return setError("Elige una propiedad.");
    if (!when) return setError("Elige el día y la hora.");
    const scheduled = new Date(when);
    if (scheduled.getTime() < Date.now() + 2 * 3600_000) return setError("Pide el fotógrafo con al menos 2 horas de anticipación.");
    if (!props.find((p) => p.id === propertyId)?.lat) return setError("Esa propiedad no tiene ubicación en el mapa. Edítala y agrégale latitud y longitud.");
    setBusy(true);
    const { error } = await supabase.from("service_requests").insert({
      property_id: propertyId,
      scheduled_at: scheduled.toISOString(),
      notes: String(f.get("notes") ?? "").trim() || null,
      address: String(f.get("address") ?? "").trim(),
      lat: null,
      lng: null,
    });
    setBusy(false);
    if (error) return setError(friendlyError(error));
    e.currentTarget.reset();
    setNotice("¡Listo! Avisamos a los fotógrafos cercanos. Aquí verás cuando uno lo acepte.");
    load();
  }

  async function cancel(id: string) {
    if (!window.confirm("¿Cancelar este pedido de fotógrafo?")) return;
    const { error } = await supabase.rpc("cancel_service", { p_request: id });
    if (error) setError(friendlyError(error));
    load();
  }

  return (
    <>
      <form className="card form grid" onSubmit={onSubmit} noValidate>
        <h2 className="span2">Pedir un fotógrafo</h2>
        {props.length === 0 ? (
          <p className="span2 muted">
            Primero <Link to="/propiedades/nueva">crea una propiedad</Link> con su ubicación.
          </p>
        ) : (
          <>
            <label className="span2">
              Propiedad
              <select name="property">
                {props.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.title}
                    {p.lat === null ? " (sin ubicación)" : ""}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Día y hora
              <input type="datetime-local" name="when" />
            </label>
            <label>
              Dirección (si es distinta a la de la propiedad)
              <input name="address" maxLength={300} />
            </label>
            <label className="span2">
              Indicaciones para el fotógrafo
              <textarea name="notes" rows={2} maxLength={500} />
            </label>
            {error && <p className="error span2">{error}</p>}
            <button type="submit" className="primary" disabled={busy}>
              {busy ? "Enviando…" : "Pedir fotógrafo"}
            </button>
          </>
        )}
      </form>
      {notice && <p className="flash" role="status">{notice}</p>}

      <h2>Mis pedidos</h2>
      {rows === null && <Loading />}
      {rows?.length === 0 && <p className="muted">Todavía no has pedido fotógrafo.</p>}
      <ul className="requests">
        {rows?.map((r) => (
          <li key={r.id} className="card request">
            <div className="row between">
              <strong>{r.property?.title ?? "Propiedad"}</strong>
              <span className="muted small">{dateFmt.format(new Date(r.scheduled_at))}</span>
            </div>
            <Timeline status={r.status} />
            {(() => {
              const expired = r.status === "pedido" && new Date(r.scheduled_at).getTime() < Date.now();
              return (
                <p className="muted small">
                  {r.photographer ? <>Fotógrafo: <strong>{r.photographer.display_name}</strong> · </> : expired ? "Ningún fotógrafo lo tomó a tiempo. Pide otro con nueva fecha. · " : r.status === "pedido" ? "Buscando fotógrafo cercano… · " : ""}
                  {r.address}
                </p>
              );
            })()}
            {r.status === "terminado" && (
              <Link to={`/propiedades/${r.property_id}`} className="button small primary">
                Subir las fotos 360 a la propiedad
              </Link>
            )}
            {(r.status === "pedido" || r.status === "aceptado") && new Date(r.scheduled_at).getTime() >= Date.now() && (
              <button type="button" className="small danger" onClick={() => cancel(r.id)}>
                Cancelar
              </button>
            )}
          </li>
        ))}
      </ul>
    </>
  );
}

function PhotographerView({ userId }: { userId: string }) {
  const [zone, setZone] = useState<{ specialty: string; base_lat: number | null; base_lng: number | null; service_radius_km: number } | null>(null);
  const [nearby, setNearby] = useState<Nearby[]>([]);
  const [jobs, setJobs] = useState<Service[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const formRef = useRef<HTMLFormElement>(null);

  const load = useCallback(async () => {
    const [z, n, j] = await Promise.all([
      supabase.from("creative_profiles").select("specialty, base_lat, base_lng, service_radius_km").eq("id", userId).maybeSingle(),
      supabase.rpc("nearby_services"),
      supabase.from("service_requests").select(SELECT).eq("photographer_id", userId).order("scheduled_at"),
    ]);
    setZone(z.data as typeof zone);
    setNearby((n.data as Nearby[]) ?? []);
    setJobs((j.data as unknown as Service[]) ?? []);
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);
  useLive(load);

  async function saveZone(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    const f = new FormData(e.currentTarget);
    const lat = Number(f.get("lat"));
    const lng = Number(f.get("lng"));
    const radius = Number(f.get("radius"));
    if (!Number.isFinite(lat) || Math.abs(lat) > 90 || !Number.isFinite(lng) || Math.abs(lng) > 180) return setError("Ubicación inválida. Usa el botón “Usar mi ubicación”.");
    if (!(radius >= 1 && radius <= 200)) return setError("El radio va de 1 a 200 km.");
    const { error } = await supabase.from("creative_profiles").update({ base_lat: lat, base_lng: lng, service_radius_km: radius }).eq("id", userId);
    if (error) return setError(friendlyError(error));
    setNotice("Zona guardada.");
    load();
  }

  function fillMyLocation() {
    const form = formRef.current;
    if (!form || !navigator.geolocation) return setError("Tu navegador no comparte la ubicación.");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        (form.elements.namedItem("lat") as HTMLInputElement).value = pos.coords.latitude.toFixed(5);
        (form.elements.namedItem("lng") as HTMLInputElement).value = pos.coords.longitude.toFixed(5);
      },
      () => setError("No pudimos leer tu ubicación. Escríbela a mano."),
    );
  }

  async function act(id: string, fn: "accept_service" | "advance_service", ok: string) {
    setError(null);
    setNotice(null);
    setBusy(id);
    const { error } = await supabase.rpc(fn, { p_request: id });
    setBusy(null);
    if (error) setError(friendlyError(error));
    else setNotice(ok);
    load();
  }

  if (!zone) return <Loading />;
  if (zone.specialty !== "fotografia")
    return (
      <div className="card empty-state">
        <h2>Solo para fotógrafos 360</h2>
        <p className="muted">
          Si tomas fotos 360, cambia tu especialidad a “Fotografía 360” en <Link to="/perfil">Mi perfil</Link> para recibir trabajos cerca de ti.
        </p>
      </div>
    );

  return (
    <>
      <form className="card form grid" onSubmit={saveZone} ref={formRef} noValidate>
        <h2 className="span2">Mi zona de trabajo</h2>
        <label>
          Latitud
          <input name="lat" defaultValue={zone.base_lat ?? ""} inputMode="decimal" />
        </label>
        <label>
          Longitud
          <input name="lng" defaultValue={zone.base_lng ?? ""} inputMode="decimal" />
        </label>
        <label>
          Radio (km)
          <input name="radius" type="number" min={1} max={200} defaultValue={zone.service_radius_km} />
        </label>
        <span className="row">
          <button type="button" className="small" onClick={fillMyLocation}>
            Usar mi ubicación
          </button>
          <button type="submit" className="small primary">
            Guardar zona
          </button>
        </span>
      </form>
      {error && <p className="error">{error}</p>}
      {notice && <p className="flash" role="status">{notice}</p>}

      <h2>Pedidos cerca de ti</h2>
      {zone.base_lat === null && <p className="muted">Guarda tu zona de trabajo para ver pedidos.</p>}
      {zone.base_lat !== null && nearby.length === 0 && <p className="muted">No hay pedidos libres en tu zona. Te aparecen aquí en cuanto llegue uno.</p>}
      <ul className="requests">
        {nearby.map((n) => (
          <li key={n.id} className="card request">
            <div className="row between">
              <strong>{n.property_title}</strong>
              <span className="badge draft">a {n.distance_km} km</span>
            </div>
            <p className="muted small">
              {[n.neighborhood, n.city].filter(Boolean).join(", ")} · {dateFmt.format(new Date(n.scheduled_at))}
            </p>
            {n.notes && <p className="request-msg">“{n.notes}”</p>}
            <button type="button" className="small primary" disabled={busy !== null} onClick={() => act(n.id, "accept_service", "¡Es tuyo! Ya puedes ver la dirección completa en “Mis trabajos”.")}>
              {busy === n.id ? "Aceptando…" : "Aceptar trabajo"}
            </button>
          </li>
        ))}
      </ul>

      <h2>Mis trabajos</h2>
      {jobs.length === 0 && <p className="muted">Aún no has aceptado trabajos.</p>}
      <ul className="requests">
        {jobs.map((j) => (
          <li key={j.id} className="card request">
            <div className="row between">
              <strong>{j.property?.title ?? "Propiedad"}</strong>
              <span className="muted small">{dateFmt.format(new Date(j.scheduled_at))}</span>
            </div>
            <Timeline status={j.status} />
            <p className="small">{j.address}</p>
            {j.notes && <p className="request-msg">“{j.notes}”</p>}
            {(j.status === "aceptado" || j.status === "en_camino") && (
              <button type="button" className="small primary" disabled={busy !== null} onClick={() => act(j.id, "advance_service", j.status === "aceptado" ? "El vendedor ya sabe que vas en camino." : "Trabajo terminado. ¡Gracias!")}>
                {j.status === "aceptado" ? "Voy en camino" : "Terminé"}
              </button>
            )}
          </li>
        ))}
      </ul>
    </>
  );
}

export default function Fotografos() {
  const { session, profile } = useAuth();
  const userId = session!.user.id;
  const isSeller = profile?.role === "vendedor";
  return (
    <section>
      <h1>{isSeller ? "Fotógrafo 360 a domicilio" : "Trabajos de fotografía 360"}</h1>
      <p className="muted">
        {isSeller
          ? "Pide un fotógrafo para tu propiedad. Los fotógrafos cercanos reciben el aviso y el primero que acepta va a tomar las fotos."
          : "Pedidos de vendedores cerca de ti. Acepta uno y avisa cuando vas en camino y cuando terminas."}
      </p>
      {isSeller ? <SellerView userId={userId} /> : <PhotographerView userId={userId} />}
    </section>
  );
}
