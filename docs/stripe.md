# Pagos con Stripe (Fase 3)

Todo corre en **modo de prueba**: no se cobra dinero real. Tarjeta de prueba: `4242 4242 4242 4242`, cualquier fecha futura y cualquier CVC.

## Qué hace cada pieza

| Pieza | Dónde | Qué hace |
|---|---|---|
| Página **Mi plan** | Consola `/plan` | Muestra Freemium, Pro y Enterprise, abre Stripe Checkout y el portal para cancelar (ZAI-32) |
| **Solicitudes** | Consola `/solicitudes` | Las cotizaciones llegan con el contacto oculto. Se desbloquean con 1 crédito o pagando $49 (ZAI-33, ZAI-34) |
| **Mis anuncios** | Consola `/anuncios` | Formulario para comprar un anuncio: $30 por día (ZAI-36) |
| `stripe-checkout` | Edge Function | Arma el cobro. El precio lo decide la base, nunca el navegador |
| `stripe-portal` | Edge Function | Portal de Stripe para cambiar tarjeta o cancelar |
| `stripe-webhook` | Edge Function | Lo **único** que cambia planes, pagos, leads desbloqueados y anuncios |
| Migraciones 0014 a 0016 | Supabase | Funciones que usa el webhook; no duplican nada si Stripe manda el mismo evento dos veces |

Los precios están en `plans.price_mxn` (planes), `lead_price_mxn()` (lead) y `ad_price_per_day_mxn()` (anuncio).

## Cómo dejarlo funcionando (una sola vez, ~20 min)

1. **Migraciones:** en Supabase → SQL Editor, corre en orden `0013` a `0016` (después de la `0012`). Luego `supabase/tests/0000_todas_las_pruebas.sql` debe decir `TODAS LAS PRUEBAS OK`.
2. **Cuenta de Stripe** en modo prueba (https://dashboard.stripe.com/test). Copia la *Secret key* (`sk_test_…`).
3. **Portal de clientes:** Stripe → Settings → Billing → Customer portal → *Activate test link* y permite cancelar suscripciones ("at end of billing period").
4. **Subir las funciones** (necesitas la CLI de Supabase: `npm i -g supabase`):
   ```
   supabase login
   supabase link --project-ref <ref del proyecto "Zaisanfy P.">
   supabase functions deploy stripe-checkout
   supabase functions deploy stripe-portal
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```
5. **Webhook:** Stripe → Developers → Webhooks → *Add endpoint*
   - URL: `https://<ref>.supabase.co/functions/v1/stripe-webhook`
   - Eventos: `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`
   - Copia el *Signing secret* (`whsec_…`).
6. **Secretos** (Supabase → Edge Functions → Secrets, o con la CLI):
   ```
   supabase secrets set STRIPE_SECRET_KEY=sk_test_... STRIPE_WEBHOOK_SECRET=whsec_... CONSOLE_URL=http://localhost:5173
   ```
   En producción, `CONSOLE_URL` es la URL publicada de la Consola.

La Consola no necesita llaves nuevas: llama las funciones con la sesión del usuario.

## Cómo probarlo (y sacar capturas)

1. Entra a la Consola como vendedor → **Mi plan** → *Contratar Pro* → paga con 4242… → regresas y el plan dice **Pro** y **10 créditos**.
2. **Límite WIP:** como Freemium publica 3 propiedades; la 4.ª muestra "Llegaste al límite de tu plan…". Con Pro ya deja.
3. **Pay-wall:** desde el Escaparate pide una cotización a un creativo. En la Consola del creativo sale borrosa con 🔒. *Desbloquear con 1 crédito* (si tiene plan) o *Pagar $49*.
4. **Anuncio:** como vendedor Pro → Mis anuncios → elige propiedad y fechas → *Pagar y anunciar*. Aparece con la etiqueta "Patrocinado" en el buscador o el muro.
5. **Cancelar:** Mi plan → *Cambiar tarjeta o cancelar* → cancela. Sigue en Pro hasta fin de mes y luego regresa a Freemium solo.

Si algo no cambia después de pagar, revisa Stripe → Webhooks → el endpoint → *Events*: ahí sale si la función respondió con error.
