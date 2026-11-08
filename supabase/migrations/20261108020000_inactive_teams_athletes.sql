-- Inativar times e atletas sem apagar nada. O histórico (jogos, gols,
-- estatísticas, pagamentos) continua; dá para reativar depois.
--
-- Atleta inativo: sai da escalação, da presença, da mensalidade, das
-- vaquinhas novas e não recebe os avisos do time.
-- Time inativo: some das buscas, dos adversários e da troca de time; não
-- conta no limite de times do plano (reativar volta a contar) e não manda
-- lembretes.

alter table public.teams add column inactive_at timestamptz;
alter table public.team_players add column inactive_at timestamptz;

create index teams_active_owner on public.teams (owner_id) where inactive_at is null;

-- ---------------------------------------------------------------------------
-- Plano: só os times ativos contam
-- ---------------------------------------------------------------------------

create or replace function private.check_team_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or (old.inactive_at is not null and new.inactive_at is null) then
    perform private.require_feature(
      new.owner_id, 'teams',
      (
        select count(*)::int from public.teams
        where owner_id = new.owner_id and inactive_at is null and id <> new.id
      )
    );
  end if;
  return new;
end;
$$;

drop trigger teams_check_plan on public.teams;
create trigger teams_check_plan
before insert or update of inactive_at on public.teams
for each row execute function private.check_team_plan();

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
      'teams', (
        select count(*) from public.teams t
        where t.owner_id = p.id and t.inactive_at is null
      ),
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
-- Avisos e lembretes: sem atletas inativos nem times inativos
-- ---------------------------------------------------------------------------

do $$
declare
  edits constant text[][] := array[
    ['private.team_followers(uuid)',
     'where p.team_id = p_team and p.profile_id is not null',
     'where p.team_id = p_team and p.profile_id is not null and p.inactive_at is null'],
    ['private.notify_fundraiser()',
     'where p.team_id = new.team_id and p.profile_id is not null',
     'where p.team_id = new.team_id and p.profile_id is not null and p.inactive_at is null'],
    ['public.request_presence(uuid,uuid)',
     'where a.team_id = p_team and a.profile_id is not null',
     'where a.team_id = p_team and a.profile_id is not null and a.inactive_at is null'],
    ['public.request_presence(uuid,uuid)',
     'and p.answer is null and a.profile_id is not null',
     'and p.answer is null and a.profile_id is not null and a.inactive_at is null'],
    ['private.send_game_reminders()',
     'where a.team_id = team and a.profile_id is not null',
     'where a.team_id = team and a.profile_id is not null and a.inactive_at is null'],
    ['private.send_game_reminders()',
     'array_remove(array[g.team_id, g.opponent_team_id], null)' || chr(10) || '    loop',
     'array_remove(array[g.team_id, g.opponent_team_id], null)' || chr(10) || '    loop'
       || chr(10) || '      continue when exists (select 1 from public.teams t'
       || ' where t.id = team and t.inactive_at is not null);'],
    ['private.send_dues_reminders()',
     'and a.profile_id is not null',
     'and a.profile_id is not null and a.inactive_at is null'],
    ['private.send_dues_reminders()',
     'where start_month <= this_month',
     'where start_month <= this_month and not exists (select 1 from public.teams t'
       || ' where t.id = team_dues.team_id and t.inactive_at is not null)']
  ];
  i int;
  def text;
  changed text;
begin
  for i in 1 .. array_length(edits, 1) loop
    def := pg_get_functiondef(edits[i][1]::regprocedure);
    changed := replace(def, edits[i][2], edits[i][3]);
    if changed = def then
      raise exception 'edit % did not match in %', i, edits[i][1];
    end if;
    execute changed;
  end loop;
end;
$$;
