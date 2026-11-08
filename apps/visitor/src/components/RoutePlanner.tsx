"use client";

import { useState } from "react";
import Link from "next/link";
import type { Property } from "@zaisanfy/schemas";
import type { RoutePlan } from "@/lib/route-plan";

const MAX_STOPS = 10; // igual que en lib/route-plan (Google Maps abre hasta 10 paradas)

type Origin = { mode: "gps"; lat?: number; lng?: number } | { mode: "address"; address: string };

export function formatDuration(seconds: number) {
  const min = Math.max(1, Math.round(seconds / 60));
  const h = Math.floor(min / 60);
  return h ? `${h} h ${min % 60} min` : `${min} min`;
}
export const formatDistance = (meters: number) =>
  meters < 1000 ? `${Math.round(meters)} m` : `${(meters / 1000).toLocaleString("es-MX", { maximumFractionDigits: 1 })} km`;

// RF-VIS-05: el visitante elige punto de salida y propiedades, y obtiene el orden más rápido para visitarlas
export default function RoutePlanner({ properties, accessToken }: { properties: Property[]; accessToken: string }) {
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(() => new Set(properties.slice(0, MAX_STOPS).map((p) => p.id)));
  const [origin, setOrigin] = useState<Origin>({ mode: "gps" });
  const [locating, setLocating] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [plan, setPlan] = useState<RoutePlan | null>(null);

  const chosen = properties.filter((p) => selected.has(p.id));
  const byId = new Map(properties.map((p) => [p.id, p]));

  function toggle(id: string) {
    setPlan(null);
    setSelected((s) => {
      const next = new Set(s);
      if (next.has(id)) next.delete(id);
      else if (next.size < MAX_STOPS) next.add(id);
      return next;
    });
  }

  function locate() {
    setError(null);
    setPlan(null);
    if (!navigator.geolocation) return setError("Tu navegador no comparte la ubicación. Escribe una dirección.");
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocating(false);
        setOrigin({ mode: "gps", lat: pos.coords.latitude, lng: pos.coords.longitude });
      },
      () => {
        setLocating(false);
        setError("No pudimos obtener tu ubicación. Revisa el permiso del navegador o escribe una dirección.");
      },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  const originReady = origin.mode === "gps" ? origin.lat !== undefined : origin.address.trim().length >= 5;

  async function calculate(e: React.FormEvent) {
    e.preventDefault();
    if (!originReady || chosen.length === 0) return;
    setLoading(true);
    setError(null);
    setPlan(null);
    try {
      const res = await fetch("/api/ruta", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
        body: JSON.stringify({
          origin: origin.mode === "gps" ? { lat: origin.lat, lng: origin.lng } : { address: origin.address },
          propertyIds: chosen.map((p) => p.id),
        }),
      });
      const json = await res.json();
      if (!res.ok) setError(json.error ?? "No pudimos calcular la ruta.");
      else setPlan(json as RoutePlan);
    } catch {
      setError("Sin conexión. Intenta de nuevo.");
    } finally {
      setLoading(false);
    }
  }

  if (!open) {
    return (
      <div className="card route-cta">
        <div>
          <h2>¿Vas a visitarlas?</h2>
          <p className="muted">Te armamos la ruta más rápida para recorrer tus propiedades guardadas y la abres en Google Maps.</p>
        </div>
        <button type="button" className="button primary" onClick={() => setOpen(true)}>
          Planear ruta de visitas
        </button>
      </div>
    );
  }

  return (
    <section className="card route-planner" aria-labelledby="route-title">
      <div className="row between">
        <h2 id="route-title">Ruta de visitas</h2>
        <button type="button" className="link" onClick={() => setOpen(false)} aria-label="Cerrar ruta">
          ✕
        </button>
      </div>

      <form onSubmit={calculate} className="form">
        <fieldset>
          <legend>1. ¿De dónde sales?</legend>
          <label className="choice">
            <input type="radio" name="origin" checked={origin.mode === "gps"} onChange={() => { setPlan(null); setOrigin({ mode: "gps" }); }} />
            Mi ubicación actual
          </label>
          {origin.mode === "gps" && (
            <div className="row origin-detail">
              <button type="button" className="small" onClick={locate} disabled={locating}>
                {locating ? "Buscando…" : origin.lat !== undefined ? "Actualizar ubicación" : "Usar mi ubicación"}
              </button>
              {origin.lat !== undefined && <span className="muted small">Ubicación lista ✓</span>}
            </div>
          )}
          <label className="choice">
            <input type="radio" name="origin" checked={origin.mode === "address"} onChange={() => { setPlan(null); setOrigin({ mode: "address", address: "" }); }} />
            Una dirección
          </label>
          {origin.mode === "address" && (
            <input
              className="origin-detail"
              type="text"
              placeholder="Calle, número, colonia y ciudad"
              value={origin.address}
              maxLength={200}
              onChange={(e) => { setPlan(null); setOrigin({ mode: "address", address: e.target.value }); }}
              aria-label="Dirección de salida"
            />
          )}
        </fieldset>

        <fieldset>
          <legend>
            2. ¿Cuáles visitas? <span className="muted small">({chosen.length} de máximo {MAX_STOPS})</span>
          </legend>
          {properties.map((p) => (
            <label key={p.id} className="choice">
              <input type="checkbox" checked={selected.has(p.id)} onChange={() => toggle(p.id)} disabled={!selected.has(p.id) && selected.size >= MAX_STOPS} />
              {p.data.title} <span className="muted small">· {p.data.location.city}</span>
            </label>
          ))}
        </fieldset>

        {error && <p className="error" role="alert">{error}</p>}
        <button type="submit" className="button primary" disabled={loading || !originReady || chosen.length === 0}>
          {loading ? "Calculando…" : "Calcular ruta más rápida"}
        </button>
      </form>

      {plan && (
        <div className="route-result" aria-live="polite">
          <p className="route-total">
            <strong>{formatDuration(plan.totalSeconds)}</strong> · {formatDistance(plan.totalMeters)}
            <span className="muted small"> {plan.source === "google" ? "en auto, estimado por Google" : "aproximado en línea recta (Google Maps te dará el tiempo exacto)"}</span>
          </p>
          <p className="muted small">Salida: {origin.mode === "gps" ? "tu ubicación actual" : origin.address}</p>
          <ol className="route-legs">
            {plan.legs.map((l) => (
              <li key={l.id}>
                <Link href={`/propiedad/${l.id}`}>{byId.get(l.id)?.data.title ?? l.title}</Link>
                <span className="muted small"> · {formatDuration(l.seconds)}, {formatDistance(l.meters)}</span>
              </li>
            ))}
          </ol>
          {plan.skipped.length > 0 && (
            <p className="muted small">
              Sin ubicación exacta, no entran en la ruta: {plan.skipped.map((s) => s.title).join(", ")}.
            </p>
          )}
          <a className="button primary" href={plan.mapsUrl} target="_blank" rel="noreferrer">
            Abrir ruta en Google Maps ↗
          </a>
        </div>
      )}
    </section>
  );
}
