"use client";

import { useEffect, useRef, useState } from "react";
import "@photo-sphere-viewer/core/index.css";

/**
 * ZAI-23 · RF-VIS-02 · Visor 360 nativo.
 * Usa Photo Sphere Viewer con la foto equirectangular (2:1) guardada en Cloudinary.
 * Funciona con mouse, con el dedo y con el giroscopio del celular (arrastrando).
 */
export default function Visor360({ url, title }: { url: string; title: string }) {
  const container = useRef<HTMLDivElement>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let viewer: { destroy: () => void } | null = null;
    let cancelled = false;
    // Se carga solo en el navegador (usa WebGL)
    import("@photo-sphere-viewer/core").then(({ Viewer }) => {
      if (cancelled || !container.current) return;
      const v = new Viewer({
        container: container.current,
        panorama: url,
        caption: title,
        loadingTxt: "Cargando recorrido 360…",
        navbar: ["zoom", "move", "caption", "fullscreen"],
        lang: {
          zoom: "Zoom",
          zoomOut: "Alejar",
          zoomIn: "Acercar",
          moveUp: "Arriba",
          moveDown: "Abajo",
          moveLeft: "Izquierda",
          moveRight: "Derecha",
          fullscreen: "Pantalla completa",
          close: "Cerrar",
          loadError: "No se pudo cargar la foto 360",
        } as never,
        touchmoveTwoFingers: false,
        mousewheelCtrlKey: true,
      });
      v.addEventListener("panorama-error", () => setError(true));
      viewer = v;
    });
    return () => {
      cancelled = true;
      viewer?.destroy();
    };
  }, [url, title]);

  if (error) return <p className="error">No se pudo cargar la foto 360.</p>;
  return <div ref={container} className="visor360" data-testid="visor360" aria-label={`Recorrido 360 de ${title}`} />;
}
