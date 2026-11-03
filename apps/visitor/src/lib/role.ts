"use client";

import { useEffect, useState } from "react";
import { browserSupabase } from "./supabase-browser";
import { useMiLista } from "./bookmarks";

export const PARTNER_URL = process.env.NEXT_PUBLIC_PARTNER_URL ?? "http://localhost:5173";

type Info = { role: string | null; name: string | null };
const infos = new Map<string, Promise<Info>>();

export function useAccount() {
  const { ready, session } = useMiLista();
  const userId = session?.user.id ?? null;
  const email = session?.user.email ?? null;
  const [info, setInfo] = useState<Info>({ role: null, name: null });

  useEffect(() => {
    if (!userId) return setInfo({ role: null, name: null });
    if (!infos.has(userId)) {
      infos.set(
        userId,
        browserSupabase().then(async (sb) => {
          const { data } = await sb.from("profiles").select("role, full_name").eq("id", userId).maybeSingle();
          return { role: (data?.role as string | undefined) ?? null, name: (data?.full_name as string | null | undefined) ?? null };
        }),
      );
    }
    let alive = true;
    infos.get(userId)!.then((r) => alive && setInfo(r));
    return () => {
      alive = false;
    };
  }, [userId]);

  const role = info.role;
  const name = info.name ?? (email ? email.split("@")[0] : null);
  return { ready, userId, email, name, role, isSocio: role === "vendedor" || role === "creativo" || role === "admin" };
}

export function forgetAccount(userId: string) {
  infos.delete(userId);
}
