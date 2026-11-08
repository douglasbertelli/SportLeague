-- Limites por cliente. Uma linha aqui vale no lugar do limite do plano
-- (plan_features) para aquela pessoa e aquela funcionalidade: quota nula =
-- sem limite, 0 = bloqueado, n = até n. Sem linha = vale o plano.
--
-- Hoje é usado no Elite: o painel do dono dá o Elite com até 3 times e
-- ajusta esse número por cliente. Só o backend (painel) grava; o app lê o
-- resultado por plan_status().

create table private.plan_overrides (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  feature text not null check (feature ~ '^[a-z_]+$'),
  quota integer check (quota >= 0),
  updated_at timestamptz not null default now(),
  primary key (profile_id, feature)
);

-- Ninguém do app lê ou grava direto (as funções abaixo são security definer).
revoke all on private.plan_overrides from public, anon, authenticated;

-- Limite que vale para a pessoa: o dela, se houver; senão, o do plano.
create or replace function private.plan_quota(uid uuid, p_feature text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case when o.profile_id is not null then o.quota else f.quota end
  from (select 1) one
  left join private.plan_overrides o
    on o.profile_id = uid and o.feature = p_feature
  left join public.plan_features f
    on f.plan = private.effective_plan(uid) and f.feature = p_feature;
$$;

-- Os limites do plano com os da pessoa por cima. O teste grátis só aparece
-- para quem está no Gratuito (quem passou para um plano pago com um teste
-- ainda em andamento não está "em teste").
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
      where t.profile_id = p.id and t.ends_at > now() and p.plan = 'free'
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
    ), '{}'::jsonb) || coalesce((
      select jsonb_object_agg(o.feature, o.quota)
      from private.plan_overrides o
      where o.profile_id = p.id
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

-- Quem já está no Elite passa a ter até 3 times (o painel ajusta depois).
insert into private.plan_overrides (profile_id, feature, quota)
select id, 'teams', 3 from public.profiles where plan = 'elite'
on conflict (profile_id, feature) do nothing;
