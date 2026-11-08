-- Pagamentos da assinatura (tela Financeiro do administrador). Quem grava é
-- o backend de pagamentos (service role) quando a cobrança existir; o
-- administrador só vê os próprios.

create table public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  plan public.subscription_plan not null default 'premium',
  amount_cents integer not null check (amount_cents >= 0),
  -- Quantos times foram cobrados no período.
  teams smallint not null default 1 check (teams >= 0),
  period_start date not null,
  period_end date not null check (period_end >= period_start),
  status text not null default 'paid'
    check (status in ('pending', 'paid', 'failed', 'refunded')),
  -- Cartão, Pix, loja… (texto livre do backend de pagamentos).
  method text check (method is null or length(trim(method)) between 1 and 40),
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create index subscription_payments_profile
  on public.subscription_payments (profile_id, period_start desc);

alter table public.subscription_payments enable row level security;

create policy "Administrador vê os próprios pagamentos"
on public.subscription_payments for select
to authenticated
using (profile_id = (select auth.uid()));
