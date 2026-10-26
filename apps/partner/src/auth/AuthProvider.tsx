import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import type { SignIn, SignUp, UserRole } from "@zaisanfy/schemas";
import { supabase } from "../lib/supabase";

/**
 * ZAI-20 / ZAI-21 · Sesión del usuario en la Consola.
 * El rol sale de public.profiles (lo crea el trigger handle_new_user al registrarse).
 */
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

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      setSession(data.session);
      setProfile(data.session ? await loadProfile(data.session.user.id) : null);
      setLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      // No se llama a Supabase dentro del callback (lo recomienda supabase-js); se hace en el siguiente tick.
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
