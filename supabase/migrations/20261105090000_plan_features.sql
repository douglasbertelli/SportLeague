-- O que cada plano libera. A lista fica nesta tabela, não no código: mudar
-- um limite ou mover uma funcionalidade de plano é alterar uma linha, vale
-- na hora para todos e não precisa de versão nova do app.
--
-- quota: null = sem limite; 0 = bloqueado; n = até n.
-- Sem linha para o plano = sem limite.
--
-- Funcionalidades:
--   teams              times que o administrador pode ter
--   championships      campeonatos em andamento (rascunho ou rodando)
--   advanced_formats   mata-mata e grupos + mata-mata (0 = só pontos corridos)
--   dues               mensalidade do time (0 = bloqueada)
--
-- Quem deixa de ter acesso não perde nada: o que já existe continua visível,
-- só criar e editar fica bloqueado (e os lembretes de mensalidade param).

create table public.plan_features (
  plan public.subscription_plan not null,
  feature text not null check (feature ~ '^[a-z_]+$'),
  quota integer check (quota >= 0),
  primary key (plan, feature)
);

alter table public.plan_features enable row level security;

-- Todos veem a comparação dos planos; só o backend (painel / service role)
-- altera.
create policy "Planos visíveis para usuários autenticados"
on public.plan_features for select
to authenticated
using (true);

insert into public.plan_features (plan, feature, quota) values
  ('free', 'teams', 1),
  ('premium', 'teams', 5),
  ('free', 'championships', 1),
  ('premium', 'championships', null),
  ('free', 'advanced_formats', 0),
  ('premium', 'advanced_formats', null),
  ('free', 'dues', 0),
  ('premium', 'dues', null);

-- ---------------------------------------------------------------------------
-- Consulta e verificação
-- ---------------------------------------------------------------------------

create or replace function private.plan_quota(uid uuid, p_feature text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select f.quota
  from public.profiles p
  join public.plan_features f on f.plan = p.plan and f.feature = p_feature
  where p.id = uid;
$$;

create or replace function private.has_feature(uid uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.plan_quota(uid, p_feature), 1) > 0;
$$;

-- Erro lido pelo app: mensagem "plan_limit:<funcionalidade>".
create or replace function private.require_feature(
  uid uuid, p_feature text, used integer default 0
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  q integer := private.plan_quota(uid, p_feature);
begin
  if q is not null and used >= q then
    raise exception 'plan_limit:%', p_feature
      using hint = 'Recurso do plano Premium.';
  end if;
end;
$$;

revoke execute on function private.plan_quota(uuid, text) from public, anon;
revoke execute on function private.has_feature(uuid, text) from public, anon;
revoke execute on function private.require_feature(uuid, text, integer) from public, anon;
grant execute on function private.plan_quota(uuid, text) to authenticated;
grant execute on function private.has_feature(uuid, text) to authenticated;
grant execute on function private.require_feature(uuid, text, integer) to authenticated;

-- O plano do usuário, os limites e quanto ele já usa (para o app mostrar
-- e bloquear antes de o banco recusar).
create or replace function public.plan_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'plan', p.plan,
    'quotas', coalesce((
      select jsonb_object_agg(f.feature, f.quota)
      from public.plan_features f where f.plan = p.plan
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

revoke execute on function public.plan_status() from public, anon;
grant execute on function public.plan_status() to authenticated;

-- ---------------------------------------------------------------------------
-- Bloqueios
-- ---------------------------------------------------------------------------

-- Times.
create or replace function private.check_team_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_feature(
    new.owner_id, 'teams',
    (select count(*)::int from public.teams where owner_id = new.owner_id)
  );
  return new;
end;
$$;

create trigger teams_check_plan
before insert on public.teams
for each row execute function private.check_team_plan();

-- Campeonatos: quantos em andamento e o formato.
create or replace function private.check_championship_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.require_feature(
      new.owner_id, 'championships',
      (
        select count(*)::int from public.championships
        where owner_id = new.owner_id and status <> 'finished'
      )
    );
  end if;
  if new.format <> 'league'
     and (tg_op = 'INSERT' or new.format is distinct from old.format) then
    perform private.require_feature(new.owner_id, 'advanced_formats');
  end if;
  return new;
end;
$$;

create trigger championships_check_plan
before insert or update of format on public.championships
for each row execute function private.check_championship_plan();

-- Mensalidade: configurar, alterar e marcar/desmarcar pagamentos. Desligar a
-- mensalidade (apagar) continua liberado.
create or replace function private.check_dues_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  team uuid := case when tg_op = 'DELETE' then old.team_id else new.team_id end;
begin
  perform private.require_feature(private.team_owner(team), 'dues');
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger team_dues_check_plan
before insert or update on public.team_dues
for each row execute function private.check_dues_plan();

create trigger team_due_payments_check_plan
before insert or delete on public.team_due_payments
for each row
when (pg_trigger_depth() = 0)
execute function private.check_dues_plan();

-- Lembretes de mensalidade só para times com o recurso.
create or replace function private.send_dues_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  today date := (now() at time zone 'America/Sao_Paulo')::date;
  this_month date := date_trunc('month', today)::date;
  month_name text := (array[
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
    'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ])[extract(month from today)::int];
  d record;
  athlete record;
  reminder_kind text;
  amount text;
  sent integer := 0;
begin
  for d in
    select * from public.team_dues
    where start_month <= this_month
      and today in (this_month + due_day - 1, this_month + due_day + 2)
      and private.has_feature(private.team_owner(team_id), 'dues')
  loop
    reminder_kind := case
      when today = this_month + d.due_day - 1 then 'due'
      else 'late'
    end;
    amount := 'R$ ' || translate(
      to_char(d.amount_cents / 100.0, 'FM999,999,990.00'), ',.', '.,'
    );

    for athlete in
      select a.id, a.profile_id
      from public.team_players a
      where a.team_id = d.team_id
        and a.profile_id is not null
        and not exists (
          select 1 from public.team_due_payments p
          where p.athlete_id = a.id and p.month = this_month
        )
        and not exists (
          select 1 from private.dues_reminders r
          where r.athlete_id = a.id and r.month = this_month and r.kind = reminder_kind
        )
    loop
      insert into private.dues_reminders (athlete_id, month, kind)
      values (athlete.id, this_month, reminder_kind);
      perform private.notify(
        athlete.profile_id,
        'dues',
        case reminder_kind
          when 'due' then 'Mensalidade vence hoje'
          else 'Mensalidade em atraso'
        end,
        'Mensalidade de ' || month_name || ' do ' || private.team_name(d.team_id)
          || ': ' || amount || '.'
          || case when d.pix_key is null then ''
             else ' PIX: ' || d.pix_key end,
        d.team_id, null, null, true
      );
      sent := sent + 1;
    end loop;
  end loop;
  return sent;
end;
$$;
