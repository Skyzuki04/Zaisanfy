-- ZAI-36 · ADS-01: el vendedor compra su anuncio con Stripe (antes solo se daba de alta a mano).
-- stripe-checkout revisa y cotiza con ad_quote(); el webhook crea el anuncio con stripe_create_ad() ya pagado.

-- Cotización: valida que la propiedad sea suya y esté publicada, que su plan permita anunciar y las fechas
create or replace function public.ad_quote(p_property uuid, p_starts date, p_ends date)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_days integer;
begin
  if not exists (select 1 from public.properties where id = p_property and seller_id = auth.uid() and status = 'published') then
    raise exception 'Solo puedes anunciar tus propiedades publicadas' using errcode = 'P0001';
  end if;
  if not (select can_advertise from public.plans where id = public.my_plan()) then
    raise exception 'Tu plan no incluye anuncios. Cámbiate a Pro o Enterprise.' using errcode = 'ZA003';
  end if;
  if p_starts is null or p_ends is null or p_ends < p_starts then
    raise exception 'La fecha de fin debe ser igual o posterior a la de inicio' using errcode = 'P0001';
  end if;
  if p_starts < (now() at time zone 'America/Mexico_City')::date then
    raise exception 'El anuncio no puede empezar en el pasado' using errcode = 'P0001';
  end if;
  v_days := p_ends - p_starts + 1;
  if v_days > 60 then
    raise exception 'Un anuncio dura máximo 60 días' using errcode = 'P0001';
  end if;
  return v_days * public.ad_price_per_day_mxn();
end;
$$;

revoke execute on function public.ad_quote from public, anon;
grant execute on function public.ad_quote to authenticated;

-- Lo llama el webhook al confirmarse el pago. Si llega dos veces, no crea dos anuncios.
create or replace function public.stripe_create_ad(
  p_user uuid, p_property uuid, p_placement public.ad_placement, p_starts date, p_ends date,
  p_amount_mxn numeric, p_payment_ref text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment uuid;
  v_ad      uuid;
begin
  if not exists (select 1 from public.properties where id = p_property and seller_id = p_user) then
    raise exception 'La propiedad % no es de %', p_property, p_user;
  end if;
  v_payment := public.stripe_record_payment(p_user, p_amount_mxn, p_payment_ref);
  select id into v_ad from public.ads where payment_id = v_payment;
  if v_ad is null then
    insert into public.ads (property_id, placement, starts_on, ends_on, payment_id)
    values (p_property, p_placement, p_starts, p_ends, v_payment)
    returning id into v_ad;
  end if;
  return v_ad;
end;
$$;

revoke execute on function public.stripe_create_ad from public, anon, authenticated;
grant execute on function public.stripe_create_ad to service_role;
