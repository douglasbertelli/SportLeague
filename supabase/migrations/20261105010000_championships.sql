-- Campeonatos. Um administrador organiza: escolhe o formato (pontos
-- corridos, mata-mata ou grupos + mata-mata), convida times da plataforma
-- (o dono do time aceita ou recusa) e inclui times fictícios dele. O app
-- sorteia e gera os jogos; o organizador marca data, hora e local de cada
-- um e lança os placares. Veem o campeonato o organizador e os membros
-- (dono, técnicos e atletas com conta) dos times da plataforma inscritos.

create table public.championships (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 3 and 60),
  modality public.team_modality not null,
  format text not null check (format in ('league', 'knockout', 'groups')),
  -- Pontos corridos e grupos: turno e returno.
  double_round boolean not null default false,
  -- Grupos + mata-mata: quantos grupos e quantos passam de cada um.
  group_count smallint check (group_count in (2, 4, 8)),
  qualifiers_per_group smallint check (qualifiers_per_group in (1, 2)),
  status text not null default 'draft'
    check (status in ('draft', 'running', 'finished')),
  created_at timestamptz not null default now(),
  constraint championships_groups_options check (
    format <> 'groups'
    or (group_count is not null and qualifiers_per_group is not null)
  )
);

create index championships_owner_id on public.championships (owner_id);

-- Times inscritos. O nome fica guardado: os times fictícios só são
-- visíveis para quem os criou, e os outros participantes também precisam ver.
create table public.championship_teams (
  id uuid primary key default gen_random_uuid(),
  championship_id uuid not null
    references public.championships (id) on delete cascade,
  team_id uuid references public.teams (id) on delete cascade,
  guest_team_id uuid references public.guest_teams (id) on delete cascade,
  name text not null default '',
  status text not null default 'invited'
    check (status in ('invited', 'accepted', 'declined')),
  -- Grupo sorteado ('A', 'B'…), no formato com grupos.
  group_label text check (group_label ~ '^[A-H]$'),
  created_at timestamptz not null default now(),
  constraint championship_teams_one_team
    check (num_nonnulls(team_id, guest_team_id) = 1),
  unique (championship_id, team_id),
  unique (championship_id, guest_team_id)
);

create index championship_teams_team_id on public.championship_teams (team_id);
create index championship_teams_guest_team_id
  on public.championship_teams (guest_team_id);

-- Jogos. No mata-mata, os jogos das fases seguintes nascem sem os times
-- (nulos = a definir) e o vencedor de cada jogo entra no seguinte.
create table public.championship_matches (
  id uuid primary key default gen_random_uuid(),
  championship_id uuid not null
    references public.championships (id) on delete cascade,
  stage text not null check (stage in ('league', 'group', 'knockout')),
  -- Rodada (pontos corridos e grupos) ou fase do mata-mata (1 = a primeira).
  round smallint not null check (round >= 1),
  -- Posição do jogo na fase do mata-mata (o chaveamento).
  slot smallint not null default 0 check (slot >= 0),
  group_label text check (group_label ~ '^[A-H]$'),
  home_id uuid references public.championship_teams (id) on delete cascade,
  away_id uuid references public.championship_teams (id) on delete cascade,
  scheduled_at timestamptz,
  venue_id uuid references public.venues (id) on delete set null,
  home_score smallint check (home_score >= 0),
  away_score smallint check (away_score >= 0),
  -- Pênaltis do mata-mata empatado.
  home_penalties smallint check (home_penalties >= 0),
  away_penalties smallint check (away_penalties >= 0),
  created_at timestamptz not null default now(),
  constraint championship_matches_score_pair
    check ((home_score is null) = (away_score is null))
);

create index championship_matches_championship
  on public.championship_matches (championship_id, stage, round, slot);
create index championship_matches_home_id on public.championship_matches (home_id);
create index championship_matches_away_id on public.championship_matches (away_id);
create index championship_matches_venue_id on public.championship_matches (venue_id);

-- ---------------------------------------------------------------------------
-- Quem vê e quem altera
-- ---------------------------------------------------------------------------

create or replace function private.is_championship_owner(p_championship uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.championships
    where id = p_championship and owner_id = uid
  );
$$;

-- O organizador e os membros dos times da plataforma inscritos (inclusive
-- convidados, para o dono do time ver o convite antes de aceitar).
create or replace function private.can_see_championship(p_championship uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_championship_owner(p_championship, uid)
    or exists (
      select 1 from public.championship_teams ct
      where ct.championship_id = p_championship
        and ct.team_id is not null
        and ct.status <> 'declined'
        and private.is_team_member(ct.team_id, uid)
    );
$$;

revoke execute on function private.is_championship_owner(uuid, uuid) from public, anon;
grant execute on function private.is_championship_owner(uuid, uuid) to authenticated;
revoke execute on function private.can_see_championship(uuid, uuid) from public, anon;
grant execute on function private.can_see_championship(uuid, uuid) to authenticated;

alter table public.championships enable row level security;
alter table public.championship_teams enable row level security;
alter table public.championship_matches enable row level security;

create policy "Organizador e times inscritos veem o campeonato"
on public.championships for select
to authenticated
using (private.can_see_championship(id, (select auth.uid())));

create policy "Administrador cria campeonato"
on public.championships for insert
to authenticated
with check (
  owner_id = (select auth.uid()) and private.is_admin((select auth.uid()))
);

create policy "Organizador altera o campeonato"
on public.championships for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy "Organizador exclui o campeonato"
on public.championships for delete
to authenticated
using (owner_id = (select auth.uid()));

create policy "Organizador e times inscritos veem os times"
on public.championship_teams for select
to authenticated
using (private.can_see_championship(championship_id, (select auth.uid())));

-- Times fictícios só os do organizador.
create policy "Organizador inscreve times"
on public.championship_teams for insert
to authenticated
with check (
  private.is_championship_owner(championship_id, (select auth.uid()))
  and (
    guest_team_id is null
    or exists (
      select 1 from public.guest_teams g
      where g.id = guest_team_id and g.owner_id = (select auth.uid())
    )
  )
);

create policy "Organizador sorteia os grupos"
on public.championship_teams for update
to authenticated
using (private.is_championship_owner(championship_id, (select auth.uid())))
with check (private.is_championship_owner(championship_id, (select auth.uid())));

create policy "Organizador tira times"
on public.championship_teams for delete
to authenticated
using (private.is_championship_owner(championship_id, (select auth.uid())));

create policy "Organizador e times inscritos veem os jogos"
on public.championship_matches for select
to authenticated
using (private.can_see_championship(championship_id, (select auth.uid())));

create policy "Organizador gera os jogos"
on public.championship_matches for insert
to authenticated
with check (private.is_championship_owner(championship_id, (select auth.uid())));

create policy "Organizador marca e lança os jogos"
on public.championship_matches for update
to authenticated
using (private.is_championship_owner(championship_id, (select auth.uid())))
with check (private.is_championship_owner(championship_id, (select auth.uid())));

create policy "Organizador remove os jogos"
on public.championship_matches for delete
to authenticated
using (private.is_championship_owner(championship_id, (select auth.uid())));

-- Inscrição: o banco põe o nome e a situação. Time do próprio organizador
-- e time fictício já entram aceitos; time de outro dono fica convidado.
create or replace function private.prepare_championship_team()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.team_id is not null then
    select t.name,
           case when t.owner_id = c.owner_id then 'accepted' else 'invited' end
    into new.name, new.status
    from public.teams t, public.championships c
    where t.id = new.team_id and c.id = new.championship_id;
  else
    select name into new.name from public.guest_teams where id = new.guest_team_id;
    new.status := 'accepted';
  end if;
  return new;
end;
$$;

revoke execute on function private.prepare_championship_team() from public, anon;

create trigger championship_teams_prepare
before insert on public.championship_teams
for each row execute function private.prepare_championship_team();

-- O dono do time convidado aceita ou recusa (antes de o campeonato começar).
create or replace function public.respond_championship_invite(
  p_entry uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry public.championship_teams;
begin
  select * into entry from public.championship_teams where id = p_entry;
  if entry.team_id is null
     or not private.is_team_owner(entry.team_id, (select auth.uid())) then
    raise exception 'only the invited team owner can answer';
  end if;
  if entry.status <> 'invited' then
    raise exception 'invite already answered';
  end if;
  if not exists (
    select 1 from public.championships
    where id = entry.championship_id and status = 'draft'
  ) then
    raise exception 'championship already started';
  end if;
  update public.championship_teams
  set status = case when p_accept then 'accepted' else 'declined' end
  where id = p_entry;
end;
$$;

revoke execute on function public.respond_championship_invite(uuid, boolean)
  from public, anon;
grant execute on function public.respond_championship_invite(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Notificações
-- ---------------------------------------------------------------------------

alter table public.notifications
  add column championship_id uuid
    references public.championships (id) on delete set null;

create index notifications_championship_id
  on public.notifications (championship_id);

create or replace function private.notify_championship(
  p_recipient uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_team uuid,
  p_championship uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null or p_recipient is not distinct from (select auth.uid()) then
    return;
  end if;
  insert into public.notifications
    (recipient_id, kind, title, body, team_id, championship_id)
  values
    (p_recipient, p_kind, p_title, p_body, p_team, p_championship);
end;
$$;

-- Dono, técnicos e atletas com conta do time.
create or replace function private.team_people(p_team uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select private.team_owner(p_team)
  union
  select private.team_followers(p_team);
$$;

revoke execute on function private.notify_championship(uuid, text, text, text, uuid, uuid)
  from public, anon;
revoke execute on function private.team_people(uuid) from public, anon;

-- Convite (para o dono do time) e resposta (para o organizador).
create or replace function private.notify_championship_team()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
begin
  select * into c from public.championships where id = new.championship_id;
  if tg_op = 'INSERT' and new.status = 'invited' then
    perform private.notify_championship(
      private.team_owner(new.team_id), 'championship_invite',
      'Convite para campeonato',
      'O ' || new.name || ' foi convidado para o campeonato ' || c.name || '.',
      new.team_id, c.id
    );
  elsif tg_op = 'UPDATE' and old.status = 'invited' and new.status <> 'invited' then
    perform private.notify_championship(
      c.owner_id, 'championship_answer',
      case when new.status = 'accepted' then 'Convite aceito' else 'Convite recusado' end,
      'O ' || new.name
        || case when new.status = 'accepted' then ' aceitou' else ' recusou' end
        || ' o convite para o campeonato ' || c.name || '.',
      new.team_id, c.id
    );
  end if;
  return new;
end;
$$;

revoke execute on function private.notify_championship_team() from public, anon;

create trigger championship_teams_notify
after insert or update on public.championship_teams
for each row execute function private.notify_championship_team();

-- Campeonato começou (tabela gerada): todos os times inscritos.
create or replace function private.notify_championship_started()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry record;
  person uuid;
begin
  if old.status <> 'draft' or new.status <> 'running' then
    return new;
  end if;
  for entry in
    select team_id from public.championship_teams
    where championship_id = new.id and team_id is not null and status = 'accepted'
  loop
    for person in select private.team_people(entry.team_id) loop
      perform private.notify_championship(
        person, 'championship_started', 'O campeonato começou',
        'A tabela do campeonato ' || new.name || ' saiu. Veja os jogos do time.',
        entry.team_id, new.id
      );
    end loop;
  end loop;
  return new;
end;
$$;

revoke execute on function private.notify_championship_started() from public, anon;

create trigger championships_notify_started
after update on public.championships
for each row execute function private.notify_championship_started();

-- Jogo marcado ou remarcado e resultado lançado: os dois times.
create or replace function private.notify_championship_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
  home public.championship_teams;
  away public.championship_teams;
  kind text;
  title text;
  body text;
  team uuid;
  person uuid;
begin
  if new.home_id is null or new.away_id is null then
    return new;
  end if;
  if new.home_score is not null
     and (old.home_score is distinct from new.home_score
       or old.away_score is distinct from new.away_score
       or old.home_penalties is distinct from new.home_penalties
       or old.away_penalties is distinct from new.away_penalties) then
    kind := 'championship_result';
  elsif new.scheduled_at is not null
     and old.scheduled_at is distinct from new.scheduled_at then
    kind := 'championship_match';
  else
    return new;
  end if;

  select * into c from public.championships where id = new.championship_id;
  select * into home from public.championship_teams where id = new.home_id;
  select * into away from public.championship_teams where id = new.away_id;

  if kind = 'championship_result' then
    title := 'Resultado no ' || c.name;
    body := home.name || ' ' || new.home_score || ' x ' || new.away_score || ' '
      || away.name
      || case when new.home_penalties is null then ''
         else ' (pênaltis ' || new.home_penalties || ' x ' || new.away_penalties || ')'
         end || '.';
  else
    title := 'Jogo marcado no ' || c.name;
    body := home.name || ' x ' || away.name || ' em '
      || private.game_when(new.scheduled_at)
      || coalesce(' · ' || (select name from public.venues where id = new.venue_id), '')
      || '.';
  end if;

  foreach team in array array_remove(array[home.team_id, away.team_id], null) loop
    for person in select private.team_people(team) loop
      perform private.notify_championship(person, kind, title, body, team, c.id);
    end loop;
  end loop;
  return new;
end;
$$;

revoke execute on function private.notify_championship_match() from public, anon;

create trigger championship_matches_notify
after update on public.championship_matches
for each row execute function private.notify_championship_match();
