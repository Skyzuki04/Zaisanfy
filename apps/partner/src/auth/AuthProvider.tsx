import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import type { SignIn, SignUp, UserRole } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";

type Profile = { id: string; role: UserRole; full_name: string | null };

type AuthState = {
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
  signIn: (data: SignIn) => Promise<string | null>;
  signUp: (data: SignUp) => Promise<{ error: string | null; needsConfirmation: boolean }>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

async function loadProfile(userId: string): Promise<Profile | null> {
  const { data } = await supabase.from("profiles").select("id, role, full_name").eq("id", userId).maybeSingle();
  return data as Profile | null;
}

async function adoptHandoff() {
  const hash = new URLSearchParams(window.location.hash.slice(1));
  if (hash.get("zs_logout")) {
    window.history.replaceState(null, "", window.location.pathname + window.location.search);
    await supabase.auth.signOut({ scope: "local" });
    return;
  }
  const access_token = hash.get("zs_at");
  const refresh_token = hash.get("zs_rt");
  if (!access_token || !refresh_token) return;
  window.history.replaceState(null, "", window.location.pathname + window.location.search);
  const { error } = await supabase.auth.setSession({ access_token, refresh_token });
  if (error) {
    await supabase.auth.signOut();
    window.location.replace("/entrar");
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    adoptHandoff().then(() => supabase.auth.getSession()).then(async ({ data }) => {
      setSession(data.session);
      setProfile(data.session ? await loadProfile(data.session.user.id) : null);
      setLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      setTimeout(async () => setProfile(newSession ? await loadProfile(newSession.user.id) : null), 0);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const value: AuthState = {
    session,
    profile,
    loading,
    async signIn({ email, password }) {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      return error ? "Correo o contraseña incorrectos" : null;
    },
    async signUp({ email, password, full_name, role }) {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { role, full_name } },
      });
      // Con confirmación de correo, Supabase responde sin error y con identities vacío si el correo ya existe
      if (error?.message === "User already registered" || data.user?.identities?.length === 0) {
        return { error: "Ese correo ya tiene una cuenta. Inicia sesión.", needsConfirmation: false };
      }
      if (error) return { error: error.message, needsConfirmation: false };
      return { error: null, needsConfirmation: !data.session };
    },
    async signOut() {
      await supabase.auth.signOut();
    },
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth debe usarse dentro de <AuthProvider>");
  return ctx;
}
