import { z } from "zod";

// Mensajes de Zod en español para todas las apps.
// Las reglas que ya traen su propio mensaje lo conservan; esto cubre las que no
// (por ejemplo .max(120) o .url()), para que nunca salga "String must contain at most…".
export const spanishErrorMap: z.ZodErrorMap = (issue, ctx) => {
  switch (issue.code) {
    case z.ZodIssueCode.invalid_type:
      if (issue.received === "undefined" || issue.received === "null") return { message: "Este dato es obligatorio." };
      if (issue.expected === "number" || issue.expected === "integer") return { message: "Escribe un número." };
      return { message: "Este dato no tiene el formato correcto." };
    case z.ZodIssueCode.too_small: {
      const n = Number(issue.minimum);
      if (issue.type === "string") return { message: n <= 1 ? "Este dato es obligatorio." : `Escribe al menos ${n} caracteres.` };
      if (issue.type === "array") return { message: `Agrega al menos ${n}.` };
      if (issue.type === "number") return { message: issue.inclusive ? `Debe ser ${n} o más.` : `Debe ser mayor a ${n}.` };
      break;
    }
    case z.ZodIssueCode.too_big: {
      const n = Number(issue.maximum);
      if (issue.type === "string") return { message: `Máximo ${n} caracteres.` };
      if (issue.type === "array") return { message: `Máximo ${n}.` };
      if (issue.type === "number") return { message: issue.inclusive ? `Debe ser ${n} o menos.` : `Debe ser menor a ${n}.` };
      break;
    }
    case z.ZodIssueCode.invalid_string:
      if (issue.validation === "email") return { message: "Escribe un correo válido." };
      if (issue.validation === "url") return { message: "Escribe una liga completa (https://…)." };
      return { message: "Este dato no tiene el formato correcto." };
    case z.ZodIssueCode.not_multiple_of:
      return { message: "Escribe un número válido." };
    case z.ZodIssueCode.invalid_enum_value:
    case z.ZodIssueCode.invalid_literal:
    case z.ZodIssueCode.invalid_union:
      return { message: "Elige una opción de la lista." };
    case z.ZodIssueCode.invalid_date:
      return { message: "Escribe una fecha válida." };
  }
  return { message: issue.message ?? (ctx.defaultError.startsWith("Invalid") ? "Este dato no es válido." : ctx.defaultError) };
};

z.setErrorMap(spanishErrorMap);
