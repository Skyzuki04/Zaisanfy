"use client";

import { useEffect, useRef, useState } from "react";
import "@photo-sphere-viewer/core/index.css";
import { cld } from "@/lib/cloudinary";

/**
 * ZAI-23 · RF-VIS-02 · Visor 360 nativo.
 * Usa Photo Sphere Viewer con la foto equirectangular (2:1) guardada en Cloudinary.
 * Funciona con mouse y con el dedo (arrastrando).
 * ZAI-26: el visor (three.js, ~500 KB) se carga hasta que la persona toca "Iniciar recorrido";
 * antes solo se muestra una vista previa ligera en WebP.
 */
export default function Visor360({ url, title }: { url: string; title: string }) {
  const container = useRef<HTMLDivElement>(null);
  const [error, setError] = useState(false);
  const [started, setStarted] = useState(false);

  useEffect(() => {
    if (!started) return;
    let viewer: { destroy: () => void } | null = null;
    let cancelled = false;
    // Se carga solo en el navegador (usa WebGL)
    import("@photo-sphere-viewer/core").then(({ Viewer }) => {
      if (cancelled || !container.current) return;
      try {
        const v = new Viewer({
          container: container.current,
          // WebP + calidad automática: la foto 360 pesa mucho menos que el original
          panorama: cld(url),
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
      } catch {
        // Navegadores o celulares sin WebGL 2: se avisa y se queda la galería normal
        setError(true);
      }
    });
    return () => {
      cancelled = true;
      viewer?.destroy();
    };
  }, [url, title, started]);

  if (error) return <p className="muted">El recorrido 360 no está disponible en este navegador. Mira las fotos abajo.</p>;
  if (!started) {
    return (
      <button type="button" className="visor360 visor360-preview" onClick={() => setStarted(true)} data-testid="visor360-start">
        <img src={cld(url, 1200)} alt={`Vista previa del recorrido 360 de ${title}`} loading="lazy" decoding="async" width={1200} height={600} />
        <span className="visor360-play">▶ Iniciar recorrido 360</span>
      </button>
    );
  }
  return <div ref={container} className="visor360" data-testid="visor360" aria-label={`Recorrido 360 de ${title}`} />;
}
