// Pruebas de las validaciones T10 del formulario y de los mensajes amigables.
// Correr con: npm test -w packages/schemas
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PropertyDataSchema, SignUpSchema, ContactRequestInputSchema, CreativePostInputSchema,
  friendlyError, authError, uploadError, imageFormatError, isPlanLimit,
} from "../src/index";

const ok = { title: "Casa en Zapopan", operation: "venta", propertyType: "casa", price: 1500000, location: { state: "Jalisco", city: "Zapopan" } };
const first = (r: { success: boolean; error?: { issues: { message: string }[] } }) => (r.success ? null : r.error!.issues[0].message);
const ENGLISH = /must|should|expected|required|invalid|string|number/i;

test("Camino feliz: una propiedad válida pasa", () => {
  assert.equal(PropertyDataSchema.safeParse(ok).success, true);
});

test("Required: título, estado y ciudad", () => {
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, title: "" })), "El título debe tener al menos 3 letras");
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, location: { state: "Jalisco", city: "" } })), "La ciudad es obligatoria");
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, title: undefined })), "Este dato es obligatorio.");
});

test("Range: precio, recámaras, baños, m², latitud y fotos", () => {
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, price: 0 })), "El precio debe ser mayor a 0");
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, bedrooms: -1 })), "Las recámaras no pueden ser negativas");
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, bathrooms: -1 })), "Los baños no pueden ser negativos");
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, areaM2: 0 })), "Los metros cuadrados deben ser mayores a 0");
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, title: "x".repeat(121) })), "El título es de máximo 120 caracteres");
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, location: { ...ok.location, lat: 91 } })), "La latitud va de -90 a 90");
  const fotos = Array.from({ length: 31 }, (_, i) => `https://x.test/${i}.jpg`);
  assert.equal(first(PropertyDataSchema.safeParse({ ...ok, media: { gallery: fotos } })), "Máximo 30 fotos");
});

test("Regex: correo, teléfono y ligas", () => {
  assert.equal(first(SignUpSchema.safeParse({ email: "no-es-correo", password: "12345678", full_name: "Ana" })), "Escribe un correo válido");
  assert.equal(first(SignUpSchema.safeParse({ email: "a@b.mx", password: "123", full_name: "Ana" })), "La contraseña debe tener al menos 8 caracteres");
  const pid = "00000000-0000-0000-0000-000000000001";
  const vacio = { preferred_times: "", message: "" }; // el formulario siempre manda estos campos
  assert.equal(
    first(ContactRequestInputSchema.safeParse({ kind: "visita", property_id: pid, phone: "tel abc", ...vacio })),
    "Escribe un teléfono válido (solo números, espacios o guiones)",
  );
  assert.equal(ContactRequestInputSchema.safeParse({ kind: "visita", property_id: pid, phone: "+52 33 1234 5678", ...vacio }).success, true);
  const post = CreativePostInputSchema.safeParse({ title: "Sesión", images: ["ftp://x"] });
  assert.equal(post.success, false);
  assert.doesNotMatch(first(post)!, ENGLISH);
});

test("Ningún mensaje del formulario sale en inglés", () => {
  const casos = [
    { ...ok, price: "abc" }, { ...ok, operation: "permuta" }, { ...ok, description: "x".repeat(2001) },
    { ...ok, bedrooms: 1.5 }, { ...ok, location: { state: "J", city: "Zapopan" } }, {},
  ];
  for (const c of casos) {
    const r = PropertyDataSchema.safeParse(c);
    assert.equal(r.success, false);
    for (const i of r.error!.issues) assert.doesNotMatch(i.message, ENGLISH, `${JSON.stringify(c).slice(0, 60)} → ${i.message}`);
  }
});

test("Unique (23505): cada restricción tiene su mensaje", () => {
  const dup = (c: string) => friendlyError({ code: "23505", message: `duplicate key value violates unique constraint "${c}"` });
  assert.equal(dup("bookmarks_pkey"), "Esta propiedad ya está en tu lista.");
  assert.equal(dup("subscriptions_one_live"), "Ya tienes un plan activo. Cámbialo desde “Mi plan”.");
  assert.equal(dup("lead_unlocks_pkey"), "Este contacto ya estaba desbloqueado. No se te cobró de nuevo.");
  assert.equal(dup("property_photos_one_panorama"), "Esta propiedad ya tiene su foto 360°. Quita la anterior para subir otra.");
  assert.equal(dup("otra_cosa"), "Ese dato ya existe. Revisa que no lo hayas guardado antes.");
});

test("Errores de la base nunca salen en inglés", () => {
  assert.equal(friendlyError({ code: "23514", message: 'new row violates check constraint "properties_price"' }), "El precio debe ser mayor a 0.");
  assert.equal(friendlyError({ code: "42501", message: "permission denied for table properties" }), "No tienes permiso para hacer esto.");
  assert.equal(friendlyError({ code: "P0001", message: "Confirma tu correo antes de enviar solicitudes" }), "Confirma tu correo antes de enviar solicitudes");
  assert.equal(friendlyError({ message: "TypeError: Failed to fetch" }), "No hay conexión. Revisa tu internet e intenta de nuevo.");
});

test("Límite WIP (ZA001): mensaje con la salida", () => {
  const e = { code: "ZA001", message: "Llegaste al límite de tu plan: 3 propiedades publicadas a la vez.", hint: "Despublica otra propiedad o mejora tu plan para publicar más." };
  assert.equal(isPlanLimit(e), true);
  assert.equal(friendlyError(e), "Llegaste al límite de tu plan: 3 propiedades publicadas a la vez. Despublica otra propiedad o mejora tu plan para publicar más.");
});

test("Errores de inicio de sesión y registro en español", () => {
  assert.equal(authError({ code: "invalid_credentials", message: "Invalid login credentials" }), "Correo o contraseña incorrectos.");
  assert.match(authError({ code: "email_not_confirmed", message: "Email not confirmed" }), /confirmas tu correo/);
  assert.match(authError({ message: "Email not confirmed" }), /confirmas tu correo/);
  assert.equal(authError({ code: "weak_password", message: "Password should be at least 8 characters." }), "La contraseña debe tener al menos 8 caracteres.");
  assert.match(authError({ code: "over_email_send_rate_limit", message: "email rate limit exceeded", status: 429 }), /demasiados intentos/);
  assert.equal(authError({ message: "User already registered" }), "Ese correo ya tiene una cuenta. Inicia sesión.");
  assert.match(authError({ code: "captcha_failed", message: "captcha protection: request disallowed" }), /robot/);
  assert.match(authError({ code: "user_banned", message: "User is banned" }), /suspendida/);
  assert.equal(authError({ message: "something new" }, "Correo o contraseña incorrectos."), "Correo o contraseña incorrectos.");
});

test("Errores al subir fotos en español", () => {
  assert.match(uploadError("File size too large. Got 12000000. Maximum is 10485760."), /10 MB/);
  assert.match(uploadError("Invalid image file"), /formato/);
  assert.match(uploadError("Failed to fetch"), /conexión/);
  assert.equal(uploadError(undefined), "No se pudo subir la imagen. Intenta de nuevo.");
});

test("BLK-01: formatos de foto por extensión aunque el navegador no mande el tipo", () => {
  assert.equal(imageFormatError("sala.jpg", "image/jpeg"), null);
  assert.equal(imageFormatError("SALA.JPG", ""), null);
  assert.equal(imageFormatError("cocina.jpeg", "image/jpeg"), null);
  assert.equal(imageFormatError("frente.png", "image/png"), null);
  assert.equal(imageFormatError("patio.webp", "image/webp"), null);
  assert.equal(imageFormatError("IMG_0001.HEIC", ""), null);
  assert.match(imageFormatError("plano.gif", "image/gif")!, /no es un formato permitido/);
  assert.match(imageFormatError("contrato.pdf", "application/pdf")!, /JPG, PNG, WEBP o HEIC/);
});

test("BLK-01: errores de Cloudinary que antes salían genéricos", () => {
  assert.match(uploadError("Upload preset must be whitelisted for unsigned uploads"), /mal configurado/);
  assert.match(uploadError("Upload preset not found"), /mal configurado/);
  assert.match(uploadError("Resolution too high. Got 30000000 pixels. Maximum is 25 Mpixels"), /25 megapíxeles/);
  assert.match(uploadError("Algo raro"), /Detalle: Algo raro/);
});
