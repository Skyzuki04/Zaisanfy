"use client";

import { useEffect, useSyncExternalStore } from "react";
import type { Session } from "@supabase/supabase-js";
import { browserSupabase } from "./supabase-browser";

type State = { ready: boolean; session: Session | null; ids: ReadonlySet<string> };

let state: State = { ready: false, session: null, ids: new Set() };
const listeners = new Set<() => void>();
let started = false;

function set(next: Partial<State>) {
  state = { ...state, ...next };
  listeners.forEach((l) => l());
}

async function loadIds(session: Session | null) {
  if (!session) return set({ ready: true, session: null, ids: new Set() });
  const sb = await browserSupabase();
  const { data } = await sb.from("bookmarks").select("property_id");
  set({ ready: true, session, ids: new Set((data ?? []).map((r) => r.property_id as string)) });
}

async function start() {
  if (started) return;
  started = true;
  const sb = await browserSupabase();
  const hash = new URLSearchParams(window.location.hash.slice(1));
  if (hash.get("zs_logout")) {
    window.history.replaceState(null, "", window.location.pathname + window.location.search);
    await sb.auth.signOut({ scope: "local" });
  }
  const at = hash.get("zs_at");
  const rt = hash.get("zs_rt");
  if (at && rt) {
    window.history.replaceState(null, "", window.location.pathname + window.location.search);
    const { error } = await sb.auth.setSession({ access_token: at, refresh_token: rt });
    if (error) await sb.auth.signOut();
  }
  sb.auth.getSession().then(({ data }) => loadIds(data.session));
  sb.auth.onAuthStateChange((event, session) => {
    if (event === "SIGNED_IN" || event === "SIGNED_OUT") setTimeout(() => loadIds(session), 0);
    else if (session) set({ session });
  });
}

function startWhenIdle() {
  const w = window as Window & { requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => number };
  if (w.requestIdleCallback) w.requestIdleCallback(() => void start(), { timeout: 2000 });
  else setTimeout(() => void start(), 200);
}

const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};
const serverState: State = { ready: false, session: null, ids: new Set() };

export function useMiLista() {
  useEffect(startWhenIdle, []);
  return useSyncExternalStore(subscribe, () => state, () => serverState);
}

export async function signOut() {
  await (await browserSupabase()).auth.signOut();
}

export async function toggleBookmark(propertyId: string): Promise<string | null> {
  const saved = state.ids.has(propertyId);
  const ids = new Set(state.ids);
  if (saved) ids.delete(propertyId);
  else ids.add(propertyId);
  set({ ids });

  const sb = await browserSupabase();
  const { error } = saved
    ? await sb.from("bookmarks").delete().eq("property_id", propertyId)
    : await sb.from("bookmarks").insert({ property_id: propertyId });
  if (error && error.code !== "23505") {
    const back = new Set(state.ids);
    if (saved) back.add(propertyId);
    else back.delete(propertyId);
    set({ ids: back });
    return "No se pudo actualizar tu lista. Intenta de nuevo.";
  }
  return null;
}
