import { z } from "zod";

export const UserRole = z.enum(["visitante", "vendedor", "creativo", "admin"]);
export type UserRole = z.infer<typeof UserRole>;

export const SignUpRole = z.enum(["visitante", "vendedor", "creativo"]);
export type SignUpRole = z.infer<typeof SignUpRole>;

export const ProfileSchema = z.object({
  id: z.string().uuid(),
  role: UserRole,
  full_name: z.string().min(2).max(120).nullable(),
  created_at: z.string(),
  updated_at: z.string(),
});
export type Profile = z.infer<typeof ProfileSchema>;

export const SignUpSchema = z.object({
  email: z.string().email("Escribe un correo válido"),
  password: z.string().min(8, "La contraseña debe tener al menos 8 caracteres"),
  full_name: z.string().min(2, "Escribe tu nombre").max(120),
  role: SignUpRole.default("visitante"),
});
export type SignUp = z.infer<typeof SignUpSchema>;

export const SignInSchema = z.object({
  email: z.string().email("Escribe un correo válido"),
  password: z.string().min(1, "Escribe tu contraseña"),
});
export type SignIn = z.infer<typeof SignInSchema>;
