"use client";

import { useEffect, useRef } from "react";

// Guarda una vista o un clic en ad_events. keepalive: el clic se guarda aunque la página cambie.
function track(adId: string, kind: "impresion" | "clic") {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return;
  fetch(`${url}/rest/v1/ad_events`, {
    method: "POST",
    keepalive: true,
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ ad_id: adId, kind }),
  }).catch(() => {});
}

// Etiqueta "Patrocinado" de la tarjeta. Cuenta una vista cuando la tarjeta se ve en pantalla (la mitad o más)
// y un clic cada vez que se abre la propiedad desde la tarjeta.
export default function SponsoredTag({ adId }: { adId: string }) {
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const card = ref.current?.closest("li");
    if (!card) return;

    const onClick = (e: MouseEvent) => {
      if ((e.target as Element).closest("a")) track(adId, "clic");
    };
    card.addEventListener("click", onClick);

    let seen = false;
    const io = new IntersectionObserver(
      (entries) => {
        if (!seen && entries.some((en) => en.isIntersecting)) {
          seen = true;
          track(adId, "impresion");
          io.disconnect();
        }
      },
      { threshold: 0.5 },
    );
    io.observe(card);

    return () => {
      card.removeEventListener("click", onClick);
      io.disconnect();
    };
  }, [adId]);

  return (
    <span ref={ref} className="tag-sponsored">
      Patrocinado
    </span>
  );
}
