-- Límite WIP del vendedor: cuántas propiedades puede tener publicadas a la vez según su plan.
-- Freemium 3 · Pro 25 · Enterprise sin límite (plans.max_published, de la 0009).
-- Usa la 0013 porque la 0011 la tiene apartada Minette y la 0012 es ZAI-38.

-- Plan vigente de cualquier usuario (my_plan() solo sirve para quien tiene la sesión)
create or replace function public.plan_of(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select plan_id from public.subscriptions
     where user_id = p_user and status in ('activa', 'en_prueba')
       and (current_period_end is null or current_period_end > now())
     limit 1),
    'freemium'
  );
$$;

revoke execute on function public.plan_of from public, anon, authenticated;

-- Candado: no deja publicar una propiedad más si ya llegó al tope de su plan.
-- Despublicar, ocultar o cerrar siempre se puede. Lo que ya estaba publicado no se toca.
create or replace function public.properties_publish_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan  text;
  v_max   integer;
  v_count integer;
begin
  if new.status <> 'published' or (tg_op = 'UPDATE' and old.status = 'published') then
    return new;
  end if;

  -- Un candado por vendedor, para que dos clics al mismo tiempo no se brinquen el límite
  perform pg_advisory_xact_lock(hashtext('publicar:' || new.seller_id::text));

  v_plan := public.plan_of(new.seller_id);
  select max_published into v_max from public.plans where id = v_plan;
  if v_max is null then
    return new;
  end if;

  select count(*) into v_count
  from public.properties
  where seller_id = new.seller_id and status = 'published' and id <> new.id;

  if v_count >= v_max then
    raise exception 'Llegaste al límite de tu plan: % propiedades publicadas a la vez.', v_max
      using errcode = 'ZA001',
            detail = format('plan=%s publicadas=%s limite=%s', v_plan, v_count, v_max),
            hint = 'Despublica otra propiedad o mejora tu plan para publicar más.';
  end if;
  return new;
end;
$$;

create trigger properties_publish_limit
before insert or update of status on public.properties
for each row execute function public.properties_publish_limit();

-- Para la Consola: plan, tope y cuántas tengo publicadas
create or replace function public.my_publish_quota()
returns table (plan_id text, plan_name text, max_published integer, published integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name, p.max_published,
         (select count(*)::integer from public.properties
          where seller_id = auth.uid() and status = 'published')
  from public.plans p
  where p.id = public.plan_of(auth.uid());
$$;

revoke execute on function public.my_publish_quota from public, anon;
grant execute on function public.my_publish_quota to authenticated;
