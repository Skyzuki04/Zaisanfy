-- ZAI-33 · RF-CRE-02 (pay-wall) y ZAI-34 · RF-CRE-03 (desbloqueo de leads)
-- Las solicitudes de cotización a un creativo llegan con el nombre y el contacto ocultos.
-- El correo y el teléfono NO salen de la base hasta que el lead se desbloquea
-- (con 1 crédito del plan o pagando con Stripe). Las solicitudes de visita al vendedor no se bloquean.

-- 1) El teléfono ya no se puede leer directo de la tabla: solo por my_inbox(), que lo oculta si toca.
--    (El correo y el nombre ya no estaban en la tabla desde la 0008.)
revoke select on public.contact_requests from authenticated;
grant select (id, property_id, creative_id, post_id, requester_id, operation, preferred_times, message,
              status, created_at, updated_at)
  on public.contact_requests to authenticated;

-- 2) ¿Está bloqueada? Solo las cotizaciones sin desbloqueo
create or replace function public.lead_is_locked(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select r.property_id is null
     and not exists (select 1 from public.lead_unlocks u where u.request_id = r.id)
  from public.contact_requests r where r.id = p_request;
$$;

revoke execute on function public.lead_is_locked from public, anon;
grant execute on function public.lead_is_locked to authenticated, service_role;

-- 3) Bandeja con el contacto oculto mientras esté bloqueada
drop function public.my_inbox();
create function public.my_inbox()
returns table (
  id uuid, kind text, property_id uuid, property_title text, creative_id uuid, post_id uuid, post_title text,
  requester_name text, requester_email text, phone text, operation text, preferred_times text, message text,
  status public.contact_status, created_at timestamptz, locked boolean, unlocked_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, public.kind(r), r.property_id, p.title, r.creative_id, r.post_id, cp.title,
         case when l.locked then left(coalesce(pr.full_name, split_part(u.email, '@', 1)), 1) || '••••••'
              else coalesce(pr.full_name, split_part(u.email, '@', 1)) end,
         case when l.locked then null else u.email end,
         case when l.locked then null else r.phone end,
         r.operation, r.preferred_times, r.message, r.status, r.created_at,
         l.locked, ul.unlocked_at
  from public.contact_requests r
  join auth.users u on u.id = r.requester_id
  left join public.profiles pr on pr.id = r.requester_id
  left join public.properties p on p.id = r.property_id
  left join public.creative_posts cp on cp.id = r.post_id
  left join public.lead_unlocks ul on ul.request_id = r.id
  cross join lateral (select r.property_id is null and ul.request_id is null as locked) l
  where auth.uid() is not null
    and public.request_recipient(r.property_id, r.creative_id, r.post_id) = auth.uid()
  order by r.created_at desc;
$$;

revoke execute on function public.my_inbox from public, anon;
grant execute on function public.my_inbox to authenticated;

-- 4) Desbloquear con 1 crédito del plan. Si ya estaba abierta, no cobra otra vez.
create or replace function public.unlock_lead_with_credit(p_request uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user     uuid := auth.uid();
  v_movement uuid;
begin
  if v_user is null then
    raise exception 'Inicia sesión para desbloquear' using errcode = '42501';
  end if;
  if not exists (select 1 from public.contact_requests r where r.id = p_request
                 and public.request_recipient(r.property_id, r.creative_id, r.post_id) = v_user) then
    raise exception 'No encontramos esta solicitud o no es tuya' using errcode = '42501';
  end if;

  -- Un candado por usuario: dos clics seguidos no gastan 2 créditos
  perform pg_advisory_xact_lock(hashtext('creditos:' || v_user::text));

  if not public.lead_is_locked(p_request) then
    return 'ya_desbloqueada';
  end if;
  if public.my_credits() < 1 then
    raise exception 'No tienes créditos. Desbloquéala con pago o mejora tu plan.' using errcode = 'ZA002';
  end if;

  insert into public.credit_movements (user_id, amount, reason) values (v_user, -1, 'desbloqueo')
  returning id into v_movement;
  insert into public.lead_unlocks (request_id, credit_movement_id) values (p_request, v_movement);
  return 'desbloqueada';
end;
$$;

revoke execute on function public.unlock_lead_with_credit from public, anon;
grant execute on function public.unlock_lead_with_credit to authenticated;

-- 5) Desbloqueo pagado con Stripe (lo llama el webhook). No cobra dos veces la misma.
create or replace function public.stripe_unlock_lead(p_user uuid, p_request uuid, p_amount_mxn numeric, p_payment_ref text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment uuid;
begin
  if not exists (select 1 from public.contact_requests r where r.id = p_request
                 and public.request_recipient(r.property_id, r.creative_id, r.post_id) = p_user) then
    raise exception 'La solicitud % no es de %', p_request, p_user;
  end if;
  v_payment := public.stripe_record_payment(p_user, p_amount_mxn, p_payment_ref);
  insert into public.lead_unlocks (request_id, payment_id) values (p_request, v_payment)
  on conflict (request_id) do nothing;
end;
$$;

revoke execute on function public.stripe_unlock_lead from public, anon, authenticated;
grant execute on function public.stripe_unlock_lead to service_role;

-- 6) Historial de créditos y desbloqueos para "Mi plan"
create or replace function public.my_credit_history()
returns table (created_at timestamptz, amount integer, reason public.credit_reason, request_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select m.created_at, m.amount, m.reason, u.request_id
  from public.credit_movements m
  left join public.lead_unlocks u on u.credit_movement_id = m.id
  where m.user_id = auth.uid()
  union all
  select u.unlocked_at, 0, 'desbloqueo'::public.credit_reason, u.request_id
  from public.lead_unlocks u join public.payments p on p.id = u.payment_id
  where p.user_id = auth.uid()
  order by 1 desc
  limit 100;
$$;

revoke execute on function public.my_credit_history from public, anon;
grant execute on function public.my_credit_history to authenticated;
