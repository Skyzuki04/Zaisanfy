import { z } from "zod";

// Mensajes de Zod en español para todas las apps.
// Las reglas que ya traen su propio mensaje lo conservan; esto cubre las que no
// (por ejemplo .max(120) o .url()), para que nunca salga "String must contain at most…".
export const spanishErrorMap: z.core.$ZodErrorMap = (issue) => {
  switch (issue.code) {
    case "invalid_type":
      if (issue.input === undefined || issue.input === null) return "Este dato es obligatorio.";
      if (issue.expected === "number" || issue.expected === "int") return "Escribe un número.";
      return "Este dato no tiene el formato correcto.";
    case "too_small": {
      const n = Number(issue.minimum);
      if (issue.origin === "string") return n <= 1 ? "Este dato es obligatorio." : `Escribe al menos ${n} caracteres.`;
      if (issue.origin === "array") return `Agrega al menos ${n}.`;
      if (issue.origin === "number") return issue.inclusive ? `Debe ser ${n} o más.` : `Debe ser mayor a ${n}.`;
      break;
    }
    case "too_big": {
      const n = Number(issue.maximum);
      if (issue.origin === "string") return `Máximo ${n} caracteres.`;
      if (issue.origin === "array") return `Máximo ${n}.`;
      if (issue.origin === "number") return issue.inclusive ? `Debe ser ${n} o menos.` : `Debe ser menor a ${n}.`;
      break;
    }
    case "invalid_format":
      if (issue.format === "email") return "Escribe un correo válido.";
      if (issue.format === "url") return "Escribe una liga completa (https://…).";
      if (issue.format === "date" || issue.format === "datetime") return "Escribe una fecha válida.";
      return "Este dato no tiene el formato correcto.";
    case "not_multiple_of":
      return "Escribe un número válido.";
    case "invalid_value":
    case "invalid_union":
      return "Elige una opción de la lista.";
  }
  return "Este dato no es válido.";
};

z.config({ customError: spanishErrorMap });
