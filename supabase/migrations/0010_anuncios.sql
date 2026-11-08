-- ZAI-36 · ADS-01: anuncios en el buscador y el muro

-- Vigente = pagado, propiedad publicada y hoy (hora de México) dentro de las fechas pagadas
create or replace function public.ad_is_live(a public.ads)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (now() at time zone 'America/Mexico_City')::date between a.starts_on and a.ends_on
     and exists (select 1 from public.payments p where p.id = a.payment_id and p.status = 'pagado')
     and exists (select 1 from public.properties pr where pr.id = a.property_id and pr.status = 'published');
$$;

-- Estadísticas del vendedor: cuántas veces se mostró y cuántos clics
create or replace function public.my_ad_stats()
returns table (
  ad_id uuid, property_id uuid, property_title text, placement public.ad_placement,
  starts_on date, ends_on date, is_live boolean, impressions bigint, clicks bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id, a.property_id, p.title, a.placement, a.starts_on, a.ends_on, public.ad_is_live(a),
         e.impressions, e.clicks
  from public.ads a
  join public.properties p on p.id = a.property_id
  cross join lateral (
    select count(*) filter (where kind = 'impresion') as impressions,
           count(*) filter (where kind = 'clic') as clicks
    from public.ad_events where ad_id = a.id
  ) e
  where auth.uid() is not null and p.seller_id = auth.uid()
  order by a.ends_on desc, a.created_at desc;
$$;

revoke execute on function public.my_ad_stats from public, anon;
grant execute on function public.my_ad_stats to authenticated;
