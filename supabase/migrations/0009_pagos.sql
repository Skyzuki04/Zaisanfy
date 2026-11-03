-- Pagos (solo el servidor escribe)

create type public.subscription_status as enum ('incompleta', 'activa', 'en_prueba', 'pago_vencido', 'cancelada');
create type public.payment_status as enum ('pendiente', 'pagado', 'fallido', 'reembolsado');
create type public.credit_reason as enum ('plan', 'desbloqueo', 'ajuste');
create type public.ad_placement as enum ('buscador', 'muro');
create type public.ad_event_kind as enum ('impresion', 'clic');

-- Planes (precios provisionales)
create table public.plans (
  id                   text primary key check (id ~ '^[a-z]+$'),
  name                 text not null unique,
  price_mxn            numeric(10, 2) not null check (price_mxn >= 0),
  stripe_price_id      text unique,
  max_published        integer check (max_published is null or max_published >= 0),
  monthly_credits      integer not null default 0 check (monthly_credits >= 0),
  can_advertise        boolean not null default false,
  sort_order           smallint not null default 0
);

comment on table public.plans is 'Planes de suscripción. max_published null = sin límite.';

insert into public.plans (id, name, price_mxn, max_published, monthly_credits, can_advertise, sort_order) values
  ('freemium',   'Freemium',   0,    3,    0,  false, 0),
  ('pro',        'Pro',        499,  25,   10, true,  1),
  ('enterprise', 'Enterprise', 1499, null, 50, true,  2);

-- Cliente de Stripe
create table public.billing_customers (
  user_id             uuid primary key references auth.users (id) on delete cascade,
  stripe_customer_id  text not null unique,
  created_at          timestamptz not null default now()
);

create table public.subscriptions (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references auth.users (id) on delete cascade,
  plan_id                 text not null references public.plans (id),
  status                  public.subscription_status not null default 'incompleta',
  stripe_subscription_id  text unique,
  current_period_start    timestamptz,
  current_period_end      timestamptz,
  cancel_at_period_end    boolean not null default false,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check (current_period_end is null or current_period_start is null or current_period_end > current_period_start)
);

create unique index subscriptions_one_live on public.subscriptions (user_id) where status in ('activa', 'en_prueba', 'pago_vencido');

create trigger subscriptions_set_updated_at
before update on public.subscriptions
for each row execute function public.set_updated_at();

-- Cobros
create table public.payments (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references auth.users (id) on delete cascade,
  amount_mxn                numeric(10, 2) not null check (amount_mxn > 0),
  status                    public.payment_status not null default 'pendiente',
  stripe_payment_intent_id  text unique,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index payments_user_idx on public.payments (user_id, created_at desc);

create trigger payments_set_updated_at
before update on public.payments
for each row execute function public.set_updated_at();

-- Cobros de cada suscripción
create table public.subscription_payments (
  payment_id       uuid primary key references public.payments (id) on delete cascade,
  subscription_id  uuid not null references public.subscriptions (id) on delete cascade
);

create index subscription_payments_sub_idx on public.subscription_payments (subscription_id);

-- Créditos (saldo = suma)
create table public.credit_movements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  amount      integer not null check (amount <> 0),
  reason      public.credit_reason not null,
  created_at  timestamptz not null default now()
);

create index credit_movements_user_idx on public.credit_movements (user_id, created_at desc);

-- Leads desbloqueados
create table public.lead_unlocks (
  request_id          uuid primary key references public.contact_requests (id) on delete cascade,
  payment_id          uuid unique references public.payments (id) on delete restrict,
  credit_movement_id  uuid unique references public.credit_movements (id) on delete restrict,
  unlocked_at         timestamptz not null default now(),
  check (num_nonnulls(payment_id, credit_movement_id) = 1)
);

-- Anuncios, vistas y clics
create table public.ads (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  placement    public.ad_placement not null,
  starts_on    date not null,
  ends_on      date not null,
  payment_id   uuid unique references public.payments (id) on delete restrict,
  created_at   timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create index ads_live_idx on public.ads (placement, starts_on, ends_on);

create table public.ad_events (
  id          bigint generated always as identity primary key,
  ad_id       uuid not null references public.ads (id) on delete cascade,
  kind        public.ad_event_kind not null,
  created_at  timestamptz not null default now()
);

create index ad_events_ad_idx on public.ad_events (ad_id, kind);

-- Consultas útiles
create or replace function public.my_plan()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select plan_id from public.subscriptions
     where user_id = auth.uid() and status in ('activa', 'en_prueba')
       and (current_period_end is null or current_period_end > now())
     limit 1),
    'freemium'
  );
$$;

create or replace function public.my_credits()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(amount), 0)::integer from public.credit_movements where user_id = auth.uid();
$$;

create or replace function public.ad_is_live(a public.ads)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select current_date between a.starts_on and a.ends_on
     and exists (select 1 from public.payments p where p.id = a.payment_id and p.status = 'pagado');
$$;

revoke execute on function public.my_plan from public, anon;
revoke execute on function public.my_credits from public, anon;
grant execute on function public.my_plan to authenticated;
grant execute on function public.my_credits to authenticated;

-- Permisos
revoke insert, update, delete on public.plans, public.billing_customers, public.subscriptions, public.payments,
  public.subscription_payments, public.lead_unlocks, public.credit_movements, public.ads from anon, authenticated;
revoke all on public.billing_customers, public.subscriptions, public.payments, public.subscription_payments,
  public.lead_unlocks, public.credit_movements from anon;
revoke update, delete on public.ad_events from anon, authenticated;

alter table public.plans enable row level security;
alter table public.billing_customers enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.lead_unlocks enable row level security;
alter table public.credit_movements enable row level security;
alter table public.ads enable row level security;
alter table public.ad_events enable row level security;

create policy "Todos ven los planes"
on public.plans for select to anon, authenticated using (true);

create policy "Cada quien ve su cliente de Stripe"
on public.billing_customers for select to authenticated using (user_id = (select auth.uid()));

create policy "Cada quien ve su suscripción"
on public.subscriptions for select to authenticated using (user_id = (select auth.uid()));

create policy "Cada quien ve sus pagos"
on public.payments for select to authenticated using (user_id = (select auth.uid()));

create policy "Cada quien ve los cobros de su suscripción"
on public.subscription_payments for select to authenticated
using (exists (select 1 from public.subscriptions s where s.id = subscription_id and s.user_id = (select auth.uid())));

create policy "Cada quien ve sus créditos"
on public.credit_movements for select to authenticated using (user_id = (select auth.uid()));

create policy "Quien recibe la solicitud ve si la desbloqueó"
on public.lead_unlocks for select to authenticated
using (exists (select 1 from public.contact_requests r where r.id = request_id
               and public.request_recipient(r.property_id, r.creative_id, r.post_id) = (select auth.uid())));

create policy "Todos ven los anuncios vigentes"
on public.ads for select to anon, authenticated
using (public.ad_is_live(ads));

create policy "El vendedor ve sus anuncios"
on public.ads for select to authenticated
using (exists (select 1 from public.properties p where p.id = property_id and p.seller_id = (select auth.uid())));

create policy "Se registran vistas y clics de anuncios vigentes"
on public.ad_events for insert to anon, authenticated
with check (exists (select 1 from public.ads a where a.id = ad_id and public.ad_is_live(a)));

create policy "El vendedor ve las estadísticas de sus anuncios"
on public.ad_events for select to authenticated
using (exists (select 1 from public.ads a join public.properties p on p.id = a.property_id
               where a.id = ad_id and p.seller_id = (select auth.uid())));

create policy "Admin ve todas las suscripciones"
on public.subscriptions for select to authenticated using ((select public.my_role()) = 'admin');
create policy "Admin ve todos los pagos"
on public.payments for select to authenticated using ((select public.my_role()) = 'admin');
create policy "Admin ve todos los anuncios"
on public.ads for select to authenticated using ((select public.my_role()) = 'admin');
