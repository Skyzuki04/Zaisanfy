import { z } from "zod";

/**
 * ZAI-20 · RNF-SEC-01 · Perfiles y roles
 *
 * Cada usuario de Supabase Auth tiene una fila en `public.profiles` con su rol.
 * El perfil lo crea la base de datos al registrarse (trigger handle_new_user).
 */

// Roles de la plataforma. Deben coincidir con el enum user_role de SQL.
export const UserRole = z.enum(["visitante", "vendedor", "creativo", "admin"]);
export type UserRole = z.infer<typeof UserRole>;

// Roles que alguien puede elegir al registrarse. Admin solo se asigna desde Supabase.
export const SignUpRole = z.enum(["visitante", "vendedor", "creativo"]);
export type SignUpRole = z.infer<typeof SignUpRole>;

/** Fila completa de la tabla `profiles`, tal como la devuelve Supabase. */
export const ProfileSchema = z.object({
  id: z.string().uuid(),
  role: UserRole,
  full_name: z.string().min(2).max(120).nullable(),
  created_at: z.string(),
  updated_at: z.string(),
});
export type Profile = z.infer<typeof ProfileSchema>;

/** Formulario de registro. role y full_name viajan en options.data de supabase.auth.signUp(). */
export const SignUpSchema = z.object({
  email: z.string().email("Escribe un correo válido"),
  password: z.string().min(8, "La contraseña debe tener al menos 8 caracteres"),
  full_name: z.string().min(2, "Escribe tu nombre").max(120),
  role: SignUpRole.default("visitante"),
});
export type SignUp = z.infer<typeof SignUpSchema>;

/** Formulario de inicio de sesión. */
export const SignInSchema = z.object({
  email: z.string().email("Escribe un correo válido"),
  password: z.string().min(1, "Escribe tu contraseña"),
});
export type SignIn = z.infer<typeof SignInSchema>;
