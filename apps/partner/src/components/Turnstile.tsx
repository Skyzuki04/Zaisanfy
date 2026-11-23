import { useEffect, useRef } from "react";

// ZAI-33 (antitrolls): captcha de Cloudflare Turnstile en el registro e inicio de sesión.
// Solo aparece si hay llave pública. La llave secreta va en Supabase → Auth → Bot and Abuse Protection.
type TurnstileApi = {
  render: (el: HTMLElement, opts: Record<string, unknown>) => string;
  remove: (id: string) => void;
};
declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

let loading: Promise<void> | null = null;
function loadScript(): Promise<void> {
  if (window.turnstile) return Promise.resolve();
  loading ??= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    s.async = true;
    s.onload = () => resolve();
    s.onerror = () => {
      loading = null;
      reject(new Error("No cargó el captcha"));
    };
    document.head.appendChild(s);
  });
  return loading;
}

/** Cambia `resetKey` para pedir un captcha nuevo (cada token sirve una sola vez). */
export default function Turnstile({ siteKey, onToken, resetKey = 0 }: { siteKey: string; onToken: (t: string | null) => void; resetKey?: number }) {
  const box = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let id: string | null = null;
    let cancelled = false;
    onToken(null);
    loadScript()
      .then(() => {
        if (cancelled || !box.current || !window.turnstile) return;
        id = window.turnstile.render(box.current, {
          sitekey: siteKey,
          language: "es",
          callback: (t: string) => onToken(t),
          "expired-callback": () => onToken(null),
          "error-callback": () => onToken(null),
        });
      })
      .catch(() => onToken(null));
    return () => {
      cancelled = true;
      if (id && window.turnstile) window.turnstile.remove(id);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [siteKey, resetKey]);

  return <div ref={box} className="captcha" />;
}
