import { useEffect, useState, type FormEvent } from "react";
import Loading from "../components/Loading";
import { Link, useLocation } from "react-router-dom";
import { supabase } from "../lib/supabase";
import { useAuth } from "../auth/AuthProvider";
import { friendlyError } from "@zaisanfy/schemas";
import { mxn, paymentNotice, startCheckout } from "../lib/pay";

// Fila de my_ad_stats(): un anuncio con sus vistas y clics
type AdStats = {
  ad_id: string;
  property_id: string;
  property_title: string;
  placement: "buscador" | "muro";
  starts_on: string;
  ends_on: string;
  is_live: boolean;
  impressions: number;
  clicks: number;
};

const PLACEMENT_LABEL: Record<AdStats["placement"], string> = { buscador: "Buscador", muro: "Muro" };
const dateFmt = new Intl.DateTimeFormat("es-MX", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
const fmtDate = (d: string) => dateFmt.format(new Date(`${d}T00:00:00Z`));
const num = new Intl.NumberFormat("es-MX");

function adState(a: AdStats) {
  if (a.is_live) return { label: "Activo", cls: "published" };
  const today = new Date().toLocaleDateString("en-CA", { timeZone: "America/Mexico_City" });
  if (a.starts_on > today) return { label: "Programado", cls: "draft" };
  if (a.ends_on < today) return { label: "Terminado", cls: "closed" };
  return { label: "En pausa", cls: "hidden" }; // pago pendiente o propiedad no publicada
}

const todayMx = () => new Date().toLocaleDateString("en-CA", { timeZone: "America/Mexico_City" });
const addDays = (d: string, n: number) => new Date(new Date(`${d}T12:00:00Z`).getTime() + n * 86400000).toISOString().slice(0, 10);
const daysBetween = (a: string, b: string) => Math.round((new Date(`${b}T12:00:00Z`).getTime() - new Date(`${a}T12:00:00Z`).getTime()) / 86400000) + 1;

// ZAI-36: comprar un anuncio con Stripe. El precio y las reglas los revisa la base (ad_quote, migración 0016).
function BuyAd() {
  const { session } = useAuth();
  const userId = session!.user.id;
  const [props, setProps] = useState<{ id: string; title: string }[] | null>(null);
  const [canAdvertise, setCanAdvertise] = useState<boolean | null>(null);
  const [perDay, setPerDay] = useState(30);
  const [propertyId, setPropertyId] = useState("");
  const [placement, setPlacement] = useState<"buscador" | "muro">("buscador");
  const [startsOn, setStartsOn] = useState(todayMx());
  const [endsOn, setEndsOn] = useState(addDays(todayMx(), 6));
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    (async () => {
      const [p, plan, price] = await Promise.all([
        supabase.from("properties").select("id, title").eq("seller_id", userId).eq("status", "published").order("title"),
        supabase.rpc("my_plan"),
        supabase.rpc("ad_price_per_day_mxn"),
      ]);
      setProps((p.data as { id: string; title: string }[]) ?? []);
      if (p.data?.[0]) setPropertyId(p.data[0].id);
      if (price.data) setPerDay(Number(price.data));
      const { data: pl } = await supabase.from("plans").select("can_advertise").eq("id", plan.data ?? "freemium").maybeSingle();
      setCanAdvertise(!!pl?.can_advertise);
    })();
  }, [userId]);

  const days = endsOn >= startsOn ? daysBetween(startsOn, endsOn) : 0;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!propertyId) return setError("Elige una propiedad publicada.");
    if (days < 1) return setError("La fecha de fin debe ser igual o posterior a la de inicio.");
    if (days > 60) return setError("Un anuncio dura máximo 60 días.");
    setBusy(true);
    const err = await startCheckout({ kind: "ad", propertyId, placement, startsOn, endsOn });
    setBusy(false);
    if (err) setError(err);
  }

  if (canAdvertise === null || props === null) return null;
  if (!canAdvertise)
    return (
      <div className="card">
        <h2>Anunciar una propiedad</h2>
        <p className="muted">Tu plan Freemium no incluye anuncios. <Link to="/plan">Cámbiate a Pro o Enterprise</Link> para anunciar.</p>
      </div>
    );
  if (props.length === 0)
    return (
      <div className="card">
        <h2>Anunciar una propiedad</h2>
        <p className="muted">Publica una propiedad primero para poder anunciarla.</p>
      </div>
    );

  return (
    <form className="card form grid buy-ad" onSubmit={onSubmit} noValidate>
      <h2 className="span2">Anunciar una propiedad</h2>
      <label className="span2">
        Propiedad
        <select value={propertyId} onChange={(e) => setPropertyId(e.target.value)}>
          {props.map((p) => (
            <option key={p.id} value={p.id}>
              {p.title}
            </option>
          ))}
        </select>
      </label>
      <label>
        Dónde
        <select value={placement} onChange={(e) => setPlacement(e.target.value as "buscador" | "muro")}>
          <option value="buscador">Buscador</option>
          <option value="muro">Muro de inspiración</option>
        </select>
      </label>
      <span />
      <label>
        Desde
        <input type="date" value={startsOn} min={todayMx()} onChange={(e) => setStartsOn(e.target.value)} />
      </label>
      <label>
        Hasta
        <input type="date" value={endsOn} min={startsOn} onChange={(e) => setEndsOn(e.target.value)} />
      </label>
      <p className="span2">
        {days > 0 ? (
          <>
            {days} {days === 1 ? "día" : "días"} × {mxn.format(perDay)} = <strong>{mxn.format(days * perDay)}</strong>
          </>
        ) : (
          "Revisa las fechas"
        )}
      </p>
      {error && <p className="error span2">{error}</p>}
      <button type="submit" className="primary" disabled={busy}>
        {busy ? "Abriendo Stripe…" : "Pagar y anunciar"}
      </button>
    </form>
  );
}

export default function MisAnuncios() {
  const [rows, setRows] = useState<AdStats[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const location = useLocation();
  const notice = paymentNotice(location.search, "¡Pago recibido! Tu anuncio aparece aquí en unos segundos.");

  useEffect(() => {
    let tries = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const load = () =>
      supabase.rpc("my_ad_stats").then(({ data, error }) => {
        if (error) setError(friendlyError(error));
        setRows(((data as AdStats[]) ?? []).map((r) => ({ ...r, impressions: Number(r.impressions), clicks: Number(r.clicks) })));
        // Al volver de Stripe el webhook tarda unos segundos
        if (notice?.startsWith("¡") && tries++ < 4) timer = setTimeout(load, 2500);
      });
    load();
    return () => clearTimeout(timer);
  }, [notice]);

  return (
    <section>
      <h1>Mis anuncios</h1>
      <p className="muted">Tus propiedades patrocinadas en el buscador y el muro: cuántas veces se mostraron y cuántos clics recibieron.</p>
      {notice && <p className="flash" role="status">{notice}</p>}
      {error && <p className="error">{error}</p>}
      <BuyAd />
      {rows === null && <Loading />}
      {rows?.length === 0 && (
        <div className="card empty-state">
          <h2>
            Todavía no tienes <em>anuncios</em>
          </h2>
          <p className="muted">Cuando anuncies una propiedad, aquí verás cuántas veces se mostró y cuántos clics recibió.</p>
          <Link to="/propiedades" className="button primary">
            Ver mis propiedades
          </Link>
        </div>
      )}
      {rows && rows.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>Propiedad</th>
              <th>Dónde</th>
              <th>Fechas pagadas</th>
              <th>Estado</th>
              <th>Veces mostrado</th>
              <th>Clics</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((a) => {
              const st = adState(a);
              return (
                <tr key={a.ad_id}>
                  <td>
                    <Link to={`/propiedades/${a.property_id}`}>{a.property_title}</Link>
                  </td>
                  <td>{PLACEMENT_LABEL[a.placement]}</td>
                  <td>
                    {fmtDate(a.starts_on)} – {fmtDate(a.ends_on)}
                  </td>
                  <td>
                    <span className={`badge ${st.cls}`}>{st.label}</span>
                  </td>
                  <td>{num.format(a.impressions)}</td>
                  <td>
                    {num.format(a.clicks)}
                    {a.impressions > 0 && <span className="muted small"> ({((a.clicks / a.impressions) * 100).toFixed(1)}%)</span>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </section>
  );
}
