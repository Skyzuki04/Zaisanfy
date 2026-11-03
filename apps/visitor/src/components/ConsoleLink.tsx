"use client";

import type { MouseEvent, ReactNode } from "react";
import { browserSupabase } from "@/lib/supabase-browser";
import { PARTNER_URL } from "@/lib/role";

export async function goToConsole(path = "/") {
  const href = `${PARTNER_URL}${path}`;
  const { data } = await (await browserSupabase()).auth.getSession();
  const s = data.session;
  window.location.href = s ? `${href}#zs_at=${encodeURIComponent(s.access_token)}&zs_rt=${encodeURIComponent(s.refresh_token)}` : `${href}#zs_logout=1`;
}

export default function ConsoleLink({ path = "/", className, children }: { path?: string; className?: string; children: ReactNode }) {
  const href = `${PARTNER_URL}${path}`;

  function onClick(e: MouseEvent<HTMLAnchorElement>) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
    e.preventDefault();
    void goToConsole(path);
  }

  return (
    <a href={href} className={className} onClick={onClick}>
      {children}
    </a>
  );
}
