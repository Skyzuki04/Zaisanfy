"use client";

import { useState } from "react";
import { cld } from "@/lib/cloudinary";

/** ZAI-23 · Galería normal: se usa siempre y es la vista principal si la propiedad no tiene foto 360. */
export default function Gallery({ images, title }: { images: string[]; title: string }) {
  const [current, setCurrent] = useState(0);
  if (images.length === 0) return <div className="gallery-empty">Sin fotos todavía</div>;
  return (
    <div className="gallery" data-testid="gallery">
      <img src={cld(images[current], 1600)} alt={`${title}, foto ${current + 1} de ${images.length}`} className="gallery-main" width={1600} height={1200} fetchPriority="high" />
      {images.length > 1 && (
        <div className="gallery-thumbs">
          {images.map((src, i) => (
            <button key={src} onClick={() => setCurrent(i)} className={i === current ? "active" : ""} aria-label={`Ver foto ${i + 1}`}>
              <img src={cld(src, 200)} alt="" loading="lazy" decoding="async" width={96} height={72} />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
