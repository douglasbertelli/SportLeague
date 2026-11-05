-- Preço dos planos e teste grátis do Premium.
--
-- Premium: R$ 30,00 por mês com 1 time, mais R$ 10,00 por time a mais (sem
-- limite de times). Teste: 15 dias, uma vez por conta, o administrador
-- começa quando quiser. Os valores ficam na tabela `plans`: mudar preço ou
-- dias do teste é alterar a linha, sem versão nova do app.
-- Ainda não há cobrança: o preço só aparece na tela de planos.

create table public.plans (
  plan public.subscription_plan primary key,
  -- Mensalidade com o primeiro time.
  monthly_cents integer not null default 0 check (monthly_cents >= 0),
  -- Cada time a mais.
  extra_team_cents integer not null default 0 check (extra_team_cents >= 0),
  -- Dias do teste grátis; nulo = sem teste.
  trial_days smallint check (trial_days > 0)
);

alter table public.plans enable row level security;

create policy "Preços visíveis para usuários autenticados"
on public.plans for select
to authenticated
using (true);

insert into public.plans (plan, monthly_cents, extra_team_cents, trial_days)
values ('free', 0, 0, null), ('premium', 3000, 1000, 15);

-- No Premium cada time a mais é cobrado: sem limite.
update public.plan_features set quota = null
where plan = 'premium' and feature = 'teams';

-- ---------------------------------------------------------------------------
-- Teste grátis
-- ---------------------------------------------------------------------------

create table private.premium_trials (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  ending_notified boolean not null default false,
  ended_notified boolean not null default false
);

-- Plano que vale agora: o assinado ou o Premium do teste em andamento.
create or replace function private.effective_plan(uid uuid)
returns public.subscription_plan
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p.plan = 'premium' then p.plan
    when exists (
      select 1 from private.premium_trials t
      where t.profile_id = p.id and t.ends_at > now()
    ) then 'premium'::public.subscription_plan
    else p.plan
  end
  from public.profiles p
  where p.id = uid;
$$;

revoke execute on function private.effective_plan(uuid) from public, anon;
grant execute on function private.effective_plan(uuid) to authenticated;

create or replace function private.plan_quota(uid uuid, p_feature text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select f.quota
  from public.plan_features f
  where f.plan = private.effective_plan(uid) and f.feature = p_feature;
$$;

-- Começa o teste (uma vez por conta, só administrador no plano Gratuito).
create or replace function public.start_premium_trial()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  days smallint;
  ends timestamptz;
begin
  if not private.is_admin(uid) then
    raise exception 'trial_unavailable';
  end if;
  if exists (
    select 1 from public.profiles where id = uid and plan <> 'free'
  ) or exists (
    select 1 from private.premium_trials where profile_id = uid
  ) then
    raise exception 'trial_used';
  end if;
  select trial_days into days from public.plans where plan = 'premium';
  if days is null then
    raise exception 'trial_unavailable';
  end if;
  ends := now() + make_interval(days => days);
  insert into private.premium_trials (profile_id, ends_at) values (uid, ends);
  return ends;
end;
$$;

revoke execute on function public.start_premium_trial() from public, anon;
grant execute on function public.start_premium_trial() to authenticated;

create or replace function public.plan_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'plan', private.effective_plan(p.id),
    'paid_plan', p.plan,
    'trial_ends_at', (
      select t.ends_at from private.premium_trials t
      where t.profile_id = p.id and t.ends_at > now()
    ),
    'trial_available', (
      p.role = 'admin'
      and p.plan = 'free'
      and not exists (
        select 1 from private.premium_trials t where t.profile_id = p.id
      )
      and exists (
        select 1 from public.plans pl
        where pl.plan = 'premium' and pl.trial_days is not null
      )
    ),
    'quotas', coalesce((
      select jsonb_object_agg(f.feature, f.quota)
      from public.plan_features f
      where f.plan = private.effective_plan(p.id)
    ), '{}'::jsonb),
    'usage', jsonb_build_object(
      'teams', (select count(*) from public.teams t where t.owner_id = p.id),
      'championships', (
        select count(*) from public.championships c
        where c.owner_id = p.id and c.status <> 'finished'
      )
    )
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Avisos do fim do teste (todo dia às 9h de Brasília)
-- ---------------------------------------------------------------------------

create or replace function private.send_trial_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  t record;
  days_left integer;
  sent integer := 0;
begin
  -- Faltando até 3 dias.
  for t in
    select * from private.premium_trials
    where not ending_notified
      and ends_at > now()
      and ends_at <= now() + interval '3 days'
  loop
    days_left := greatest(1, ceil(extract(epoch from t.ends_at - now()) / 86400)::int);
    update private.premium_trials set ending_notified = true
    where profile_id = t.profile_id;
    perform private.notify(
      t.profile_id, 'plan', 'Seu teste do Premium está acabando',
      case when days_left = 1 then 'Falta 1 dia' else 'Faltam ' || days_left || ' dias' end
        || ' para o fim do teste. Depois, mensalidade, mata-mata e mais times '
        || 'ficam no plano Premium.'
    );
    sent := sent + 1;
  end loop;

  -- Terminou.
  for t in
    select * from private.premium_trials
    where not ended_notified and ends_at <= now()
  loop
    update private.premium_trials set ended_notified = true, ending_notified = true
    where profile_id = t.profile_id;
    -- Quem assinou não precisa do aviso.
    if exists (
      select 1 from public.profiles where id = t.profile_id and plan = 'free'
    ) then
      perform private.notify(
        t.profile_id, 'plan', 'Seu teste do Premium terminou',
        'Seus times, campeonatos e mensalidades continuam salvos. Criar mais '
          || 'e editar o que é do Premium fica bloqueado no plano Gratuito.'
      );
      sent := sent + 1;
    end if;
  end loop;
  return sent;
end;
$$;

select cron.schedule(
  'trial-reminders',
  '0 12 * * *',
  $$select private.send_trial_reminders()$$
);
