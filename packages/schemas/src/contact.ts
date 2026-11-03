import { z } from "zod";

export const ContactKind = z.enum(["visita", "cotizacion"]);
export type ContactKind = z.infer<typeof ContactKind>;

export const ContactStatus = z.enum(["nueva", "contactado", "agendada", "cerrada"]);
export type ContactStatus = z.infer<typeof ContactStatus>;

export const CONTACT_STATUS_LABEL: Record<ContactStatus, string> = {
  nueva: "Nueva",
  contactado: "Contactado",
  agendada: "Visita agendada",
  cerrada: "Cerrada",
};

export const CONTACT_KIND_LABEL: Record<ContactKind, string> = {
  visita: "Visita a propiedad",
  cotizacion: "Cotización",
};

const optionalText = (max: number, msg: string) =>
  z.preprocess((v) => (typeof v === "string" && v.trim() === "" ? null : typeof v === "string" ? v.trim() : v), z.string().max(max, msg).nullable());

export const ContactRequestInputSchema = z
  .object({
    kind: ContactKind,
    property_id: z.string().uuid().nullable().default(null),
    creative_id: z.string().uuid().nullable().default(null),
    post_id: z.string().uuid().nullable().default(null),
    operation: z.preprocess((v) => (v === "" ? null : v), z.enum(["venta", "renta"]).nullable().default(null)),
    phone: z.preprocess(
      (v) => (typeof v === "string" && v.trim() === "" ? null : typeof v === "string" ? v.trim() : v),
      z.string().regex(/^[+\d][\d\s()-]{6,29}$/, "Escribe un teléfono válido (solo números, espacios o guiones)").nullable(),
    ),
    preferred_times: optionalText(200, "Los horarios no pueden pasar de 200 caracteres"),
    message: optionalText(1000, "El mensaje no puede pasar de 1000 caracteres"),
  })
  .refine((d) => (d.kind === "visita" ? !!d.property_id && !d.creative_id : !!d.creative_id && !d.property_id), {
    message: "La solicitud debe ser de una propiedad o para un creativo",
  });
export type ContactRequestInput = z.infer<typeof ContactRequestInputSchema>;

export const ContactRequestSchema = z.object({
  id: z.string().uuid(),
  kind: ContactKind,
  property_id: z.string().uuid().nullable(),
  creative_id: z.string().uuid().nullable(),
  post_id: z.string().uuid().nullable(),
  requester_id: z.string().uuid(),
  phone: z.string().nullable(),
  operation: z.enum(["venta", "renta"]).nullable(),
  preferred_times: z.string().nullable(),
  message: z.string().nullable(),
  status: ContactStatus,
  created_at: z.string(),
  updated_at: z.string(),
});
export type ContactRequest = z.infer<typeof ContactRequestSchema>;

export const CONTACT_SELECT = "*, kind";

export type InboxRow = {
  id: string;
  kind: ContactKind;
  property_id: string | null;
  property_title: string | null;
  creative_id: string | null;
  post_id: string | null;
  post_title: string | null;
  requester_name: string | null;
  requester_email: string | null;
  phone: string | null;
  operation: "venta" | "renta" | null;
  preferred_times: string | null;
  message: string | null;
  status: ContactStatus;
  created_at: string;
};
