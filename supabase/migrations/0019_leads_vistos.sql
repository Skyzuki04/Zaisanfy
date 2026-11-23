-- ZAI-35 · RF-VEN-03: cada lead muestra si ya fue visto. Se marca solo al abrir la bandeja.
alter table public.contact_requests add column seen_at timestamptz;
comment on column public.contact_requests.seen_at is 'Cuándo lo vio por primera vez quien lo recibe (null = nuevo).';

-- El cliente lo puede leer (para saber si ya lo vieron); nadie lo escribe directo
grant select (seen_at) on public.contact_requests to authenticated;

-- Bandeja con seen_at
drop function public.my_inbox();
create function public.my_inbox()
returns table (
  id uuid, kind text, property_id uuid, property_title text, creative_id uuid, post_id uuid, post_title text,
  requester_name text, requester_email text, phone text, operation text, preferred_times text, message text,
  status public.contact_status, created_at timestamptz, locked boolean, unlocked_at timestamptz, seen_at timestamptz
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
         l.locked, ul.unlocked_at, r.seen_at
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

-- Marca como vistos los leads que recibí (solo los míos y solo la primera vez)
create or replace function public.mark_inbox_seen(p_ids uuid[])
returns integer
language sql
security definer
set search_path = ''
as $$
  with done as (
    update public.contact_requests r set seen_at = now()
    where r.id = any(p_ids) and r.seen_at is null
      and public.request_recipient(r.property_id, r.creative_id, r.post_id) = auth.uid()
    returning 1
  )
  select count(*)::integer from done;
$$;

revoke execute on function public.mark_inbox_seen from public, anon;
grant execute on function public.mark_inbox_seen to authenticated;
