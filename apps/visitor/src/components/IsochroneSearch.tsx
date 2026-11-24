"use client";

import "leaflet/dist/leaflet.css";
import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { Map as LeafletMap, LayerGroup, CircleMarker } from "leaflet";
import type { Isochrone, LatLng, Minutes, Zone } from "@/lib/isochrone";

const MINUTES: Minutes[] = [10, 20, 30]; // igual que en lib/isochrone
const MEXICO: [number, number] = [23.6, -102.5];

export type MapProperty = { id: string; title: string; lat: number; lng: number };

type Props = {
  isochrone: Isochrone | null; // la zona ya calculada en el servidor (si el visitante buscó por tiempo)
  properties: MapProperty[]; // resultados con coordenadas, para ponerlos en el mapa
  otherParams: string; // los demás filtros del buscador, para no perderlos
};

const GOLD = "#c9a876";
// GeoJSON trae [lng, lat]; Leaflet quiere [lat, lng]
const ring = (r: number[][]) => r.map(([lng, lat]) => [lat, lng] as [number, number]);
const toLeaflet = (z: Zone) => (z.type === "Polygon" ? z.coordinates.map(ring) : z.coordinates.map((p) => p.map(ring)));

// ZAI-38 · GEO-01: el visitante elige un punto y un tiempo, y ve la zona a la que llega en auto
export default function IsochroneSearch({ isochrone, properties, otherParams }: Props) {
  const router = useRouter();
  const [open, setOpen] = useState(Boolean(isochrone));
  const [point, setPoint] = useState<LatLng | null>(isochrone?.center ?? null);
  const [minutes, setMinutes] = useState<Minutes>(isochrone?.minutes ?? 20);
  const [locating, setLocating] = useState(false);
  const [searching, startSearch] = useTransition();
  const [ready, setReady] = useState(false); // el mapa ya se creó
  const [error, setError] = useState<string | null>(null);

  const mapEl = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const resultsLayer = useRef<LayerGroup | null>(null);
  const pointMarker = useRef<CircleMarker | null>(null);
  const leaflet = useRef<typeof import("leaflet") | null>(null);

  // 1. Crear el mapa (Leaflet solo funciona en el navegador, por eso se importa aquí adentro)
  useEffect(() => {
    if (!open || !mapEl.current || mapRef.current) return;
    let cancelled = false;
    import("leaflet").then((L) => {
      if (cancelled || !mapEl.current) return;
      leaflet.current = L;
      const map = L.map(mapEl.current, { scrollWheelZoom: false, zoomSnap: 0.25 }).setView(MEXICO, 5);
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(map);
      map.on("click", (e) => {
        setError(null);
        setPoint({ lat: e.latlng.lat, lng: e.latlng.lng });
      });
      mapRef.current = map;
      resultsLayer.current = L.layerGroup().addTo(map);
      setReady(true);
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  // Al cerrar el panel se destruye el mapa para no dejarlo colgado
  useEffect(() => {
    if (open) return;
    mapRef.current?.remove();
    mapRef.current = null;
    pointMarker.current = null;
    setReady(false);
  }, [open]);

  // 2. Dibujar la zona y las propiedades que llegaron del servidor
  useEffect(() => {
    const L = leaflet.current;
    const map = mapRef.current;
    const layer = resultsLayer.current;
    if (!L || !map || !layer) return;
    layer.clearLayers();
    const bounds = L.latLngBounds([]);
    if (isochrone) {
      const zone = L.polygon(toLeaflet(isochrone.zone), { color: GOLD, weight: 2, fillColor: GOLD, fillOpacity: 0.18 }).addTo(layer);
      bounds.extend(zone.getBounds());
    }
    for (const p of properties) {
      L.circleMarker([p.lat, p.lng], { radius: 7, color: "#1a1613", weight: 2, fillColor: "#fff", fillOpacity: 1 })
        .bindPopup(`<a href="/propiedad/${p.id}">${escapeHtml(p.title)}</a>`)
        .addTo(layer);
      bounds.extend([p.lat, p.lng]);
    }
    if (bounds.isValid()) map.fitBounds(bounds, { padding: [24, 24], maxZoom: 14 });
  }, [ready, isochrone, properties]);

  // 3. El punto elegido (clic en el mapa o ubicación del navegador)
  useEffect(() => {
    const L = leaflet.current;
    const map = mapRef.current;
    if (!L || !map) return;
    if (!point) {
      pointMarker.current?.remove();
      pointMarker.current = null;
      return;
    }
    if (!pointMarker.current) {
      pointMarker.current = L.circleMarker([point.lat, point.lng], { radius: 9, color: "#fff", weight: 3, fillColor: GOLD, fillOpacity: 1 })
        .bindTooltip("Tu punto")
        .addTo(map);
    } else pointMarker.current.setLatLng([point.lat, point.lng]);
  }, [ready, point]);

  function locate() {
    setError(null);
    if (!navigator.geolocation) return setError("Tu navegador no comparte la ubicación. Da clic en el mapa.");
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocating(false);
        const p = { lat: pos.coords.latitude, lng: pos.coords.longitude };
        setPoint(p);
        mapRef.current?.setView([p.lat, p.lng], 12);
      },
      () => {
        setLocating(false);
        setError("No pudimos obtener tu ubicación. Revisa el permiso del navegador o da clic en el mapa.");
      },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }

  // 4. Buscar: la zona y el filtro se calculan en el servidor (ahí está la llave de Mapbox)
  function search() {
    if (!point) return setError("Primero elige tu punto: da clic en el mapa o usa tu ubicación.");
    const sp = new URLSearchParams(otherParams);
    sp.set("cerca", `${point.lat.toFixed(3)},${point.lng.toFixed(3)}`);
    sp.set("tiempo", String(minutes));
    startSearch(() => router.push(`/?${sp.toString()}`, { scroll: false }));
  }

  function clear() {
    setPoint(null);
    setOpen(false);
    startSearch(() => router.push(otherParams ? `/?${otherParams}` : "/", { scroll: false }));
  }

  if (!open) {
    return (
      <div className="card route-cta iso-cta">
        <div>
          <h2>¿Qué tan lejos te queda?</h2>
          <p className="muted">Elige un lugar que te importe, como tu trabajo o la escuela, y ve solo las propiedades a 10, 20 o 30 minutos en auto.</p>
        </div>
        <button type="button" className="button primary" onClick={() => setOpen(true)}>
          Buscar por tiempo de traslado
        </button>
      </div>
    );
  }

  return (
    <section className="card iso-search" aria-labelledby="iso-title">
      <div className="iso-head">
        <div>
          <h2 id="iso-title">Buscar por tiempo de traslado</h2>
          <p className="muted small">Da clic en el mapa para elegir tu punto, o usa tu ubicación.</p>
        </div>
        <button type="button" className="link" onClick={() => setOpen(false)} aria-label="Cerrar búsqueda por tiempo">
          ✕
        </button>
      </div>

      <div ref={mapEl} className="iso-map" role="application" aria-label="Mapa: da clic para elegir tu punto" />

      <div className="iso-controls">
        <button type="button" className="small" onClick={locate} disabled={locating}>
          {locating ? "Buscando…" : "Usar mi ubicación"}
        </button>
        <div className="iso-minutes" role="radiogroup" aria-label="Tiempo en auto">
          {MINUTES.map((m) => (
            <button
              key={m}
              type="button"
              role="radio"
              aria-checked={minutes === m}
              className={`chip ${minutes === m ? "active" : ""}`}
              onClick={() => setMinutes(m)}
            >
              {m} min
            </button>
          ))}
        </div>
        <button type="button" className="button primary" onClick={search} disabled={searching || !point}>
          {searching ? "Buscando…" : "Ver propiedades en esta zona"}
        </button>
        {isochrone && (
          <button type="button" className="link" onClick={clear}>
            Quitar zona
          </button>
        )}
      </div>

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {isochrone && (
        <p className="muted small" aria-live="polite">
          Zona a {isochrone.minutes} min en auto{" "}
          {isochrone.source === "mapbox" ? "según las calles (Mapbox)." : "aproximada en línea recta (falta configurar Mapbox)."}{" "}
          {properties.length === 0 ? "No hay propiedades con ubicación dentro." : `${properties.length} en el mapa.`}
        </p>
      )}
    </section>
  );
}

function escapeHtml(s: string) {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}
