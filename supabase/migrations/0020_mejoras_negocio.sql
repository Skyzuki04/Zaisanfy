-- Mejoras de reglas de negocio (23 nov)
-- 1) ZAI-36: no se puede pagar un anuncio encimado con otro ya pagado (misma propiedad, mismo lugar, mismas fechas).
-- 2) ZAI-39: un pedido de fotógrafo que venció sin que nadie lo tomara se cancela solo al pedir otro.

drop function public.ad_quote(uuid, date, date);

create or replace function public.ad_quote(p_property uuid, p_starts date, p_ends date, p_placement public.ad_placement default null)
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
  -- No pagar dos veces por lo mismo: otro anuncio pagado de esta propiedad, en el mismo lugar y con fechas encimadas
  if exists (select 1 from public.ads a join public.payments pay on pay.id = a.payment_id and pay.status = 'pagado'
             where a.property_id = p_property and (p_placement is null or a.placement = p_placement)
               and a.starts_on <= p_ends and a.ends_on >= p_starts) then
    raise exception 'Ya tienes un anuncio de esta propiedad ahí en esas fechas. Elige otras fechas u otro lugar.' using errcode = 'ZA006';
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

create or replace function public.service_requests_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.properties;
begin
  new.seller_id := auth.uid();
  select * into p from public.properties where id = new.property_id;
  if p.id is null or p.seller_id is distinct from new.seller_id then
    raise exception 'Solo puedes pedir fotógrafo para tus propiedades' using errcode = '42501';
  end if;
  -- Un pedido viejo que nadie tomó ya no estorba: se cancela solo para poder pedir otro
  update public.service_requests set status = 'cancelado'
   where property_id = new.property_id and status = 'pedido' and scheduled_at < now();
  if new.scheduled_at < now() + interval '2 hours' then
    raise exception 'Pide el fotógrafo con al menos 2 horas de anticipación' using errcode = 'P0001';
  end if;
  if new.scheduled_at > now() + interval '60 days' then
    raise exception 'Solo se puede agendar hasta 60 días adelante' using errcode = 'P0001';
  end if;
  new.lat := coalesce(new.lat, p.lat);
  new.lng := coalesce(new.lng, p.lng);
  if new.lat is null or new.lng is null then
    raise exception 'La propiedad no tiene ubicación en el mapa. Agrégale latitud y longitud.' using errcode = 'P0001';
  end if;
  new.address := coalesce(nullif(trim(new.address), ''),
                          concat_ws(', ', p.address, p.neighborhood, p.city, p.state));
  new.status := 'pedido';
  new.photographer_id := null;
  new.accepted_at := null;
  new.finished_at := null;
  new.created_at := now();
  new.updated_at := now();
  return new;
end;
$$;

