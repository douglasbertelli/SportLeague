-- Jogos do campeonato no dia a dia dos times (etapa 2). Cada jogo do
-- campeonato com os dois times e a data vira um jogo (`games`, tipo
-- 'championship'): aparece na aba Jogos, com relógio, placar ao vivo,
-- súmula, escalação, presença e lembretes. O time da plataforma mandante
-- fica como "quem marcou" (controla o relógio e o placar); se o mandante é
-- fictício, o visitante da plataforma assume, jogando fora.
--
-- Sincronização:
--   * campeonato -> jogo: times, data, local e placar lançado pelo
--     organizador;
--   * jogo -> campeonato: o placar que o mandante lança (ou soma ao vivo)
--     volta para a classificação; no mata-mata, o vencedor avança.
-- O jogo de campeonato não passa pelas regras do amistoso (convite,
-- disponibilidade, mando) nem pelos avisos de amistoso (o campeonato tem os
-- dele). Os times não editam nem cancelam: só o placar e o relógio.

alter table public.games
  add column championship_match_id uuid unique
    references public.championship_matches (id) on delete cascade;

-- ---------------------------------------------------------------------------
-- Regras do amistoso: só para amistosos
-- ---------------------------------------------------------------------------

drop trigger games_check_modality on public.games;
create trigger games_check_modality
before insert or update on public.games
for each row when (new.type <> 'championship')
execute function public.check_game_modality();

drop trigger games_check_sides on public.games;
create trigger games_check_sides
before insert or update on public.games
for each row when (new.type <> 'championship')
execute function public.check_game_sides();

drop trigger games_check_slot on public.games;
create trigger games_check_slot
before insert or update on public.games
for each row when (new.type <> 'championship')
execute function public.check_game_slot();

drop trigger games_check_status on public.games;
create trigger games_check_status
before insert or update on public.games
for each row when (new.type <> 'championship')
execute function public.check_game_status();

drop trigger games_check_score on public.games;
create trigger games_check_score
before update on public.games
for each row when (new.type <> 'championship')
execute function public.check_game_score();

drop trigger games_notify on public.games;
create trigger games_notify
after insert or update on public.games
for each row when (new.type <> 'championship')
execute function private.notify_game();

-- Jogo de campeonato: nasce marcado; o time só mexe no placar e no relógio
-- (o resto vem do campeonato, pela sincronização).
create or replace function private.check_championship_game()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  editable constant text[] := array[
    'team_score', 'opponent_score', 'match_phase', 'clock_started_at',
    'clock_elapsed', 'period_minutes', 'updated_at'
  ];
begin
  if tg_op = 'INSERT' then
    if pg_trigger_depth() < 2 then
      raise exception 'championship games come from the championship';
    end if;
    new.status := 'scheduled';
    new.canceled_by_team_id := null;
    new.cancel_reason := null;
    return new;
  end if;
  -- A sincronização do campeonato passa.
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  if (to_jsonb(new) - editable) is distinct from (to_jsonb(old) - editable) then
    raise exception 'championship games are managed by the organizer';
  end if;
  if (new.team_score is null) <> (new.opponent_score is null) then
    raise exception 'both scores are required';
  end if;
  if new.team_score < 0 or new.opponent_score < 0 then
    raise exception 'scores cannot be negative';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_championship_game() from public, anon;

create trigger games_check_championship
before insert or update on public.games
for each row when (new.type = 'championship')
execute function private.check_championship_game();

-- ---------------------------------------------------------------------------
-- Campeonato -> jogo
-- ---------------------------------------------------------------------------

create or replace function private.sync_championship_game()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
  home public.championship_teams;
  away public.championship_teams;
  host public.championship_teams;
  rival public.championship_teams;
  home_side boolean;
  game_id uuid;
  host_score smallint;
  rival_score smallint;
begin
  select id into game_id from public.games where championship_match_id = new.id;

  if new.home_id is not null and new.away_id is not null then
    select * into home from public.championship_teams where id = new.home_id;
    select * into away from public.championship_teams where id = new.away_id;
  end if;

  -- Sem os dois times, sem data ou sem time da plataforma: sem jogo.
  if new.scheduled_at is null
     or home.id is null or away.id is null
     or (home.team_id is null and away.team_id is null) then
    if game_id is not null then
      delete from public.games where id = game_id;
    end if;
    return new;
  end if;

  select * into c from public.championships where id = new.championship_id;
  home_side := home.team_id is not null;
  host := case when home_side then home else away end;
  rival := case when home_side then away else home end;
  host_score := case when home_side then new.home_score else new.away_score end;
  rival_score := case when home_side then new.away_score else new.home_score end;

  if game_id is null then
    insert into public.games (
      team_id, opponent, scheduled_at, type, modality, opponent_team_id,
      opponent_guest_id, host_is_home, venue_id, team_score, opponent_score,
      championship_match_id
    ) values (
      host.team_id, rival.name, new.scheduled_at, 'championship', c.modality,
      rival.team_id, rival.guest_team_id, home_side, new.venue_id,
      host_score, rival_score, new.id
    );
  else
    update public.games set
      team_id = host.team_id,
      opponent = rival.name,
      scheduled_at = new.scheduled_at,
      modality = c.modality,
      opponent_team_id = rival.team_id,
      opponent_guest_id = rival.guest_team_id,
      host_is_home = home_side,
      venue_id = new.venue_id,
      team_score = host_score,
      opponent_score = rival_score
    where id = game_id
      and (team_id, opponent, scheduled_at, opponent_team_id, opponent_guest_id,
           host_is_home, venue_id, team_score, opponent_score)
          is distinct from
          (host.team_id, rival.name, new.scheduled_at, rival.team_id,
           rival.guest_team_id, home_side, new.venue_id, host_score,
           rival_score);
  end if;
  return new;
end;
$$;

revoke execute on function private.sync_championship_game() from public, anon;

create trigger championship_matches_sync_game
after insert or update on public.championship_matches
for each row execute function private.sync_championship_game();

-- ---------------------------------------------------------------------------
-- Jogo -> campeonato (o placar do mandante)
-- ---------------------------------------------------------------------------

create or replace function private.sync_game_to_championship()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Só o que o time lançou (a sincronização do campeonato não volta).
  if pg_trigger_depth() > 1
     or (new.team_score is not distinct from old.team_score
         and new.opponent_score is not distinct from old.opponent_score) then
    return new;
  end if;
  update public.championship_matches set
    home_score = case when new.host_is_home then new.team_score else new.opponent_score end,
    away_score = case when new.host_is_home then new.opponent_score else new.team_score end,
    -- Placar novo: os pênaltis (se houver) o organizador lança de novo.
    home_penalties = null,
    away_penalties = null
  where id = new.championship_match_id;
  return new;
end;
$$;

revoke execute on function private.sync_game_to_championship() from public, anon;

create trigger games_sync_championship
after update on public.games
for each row when (new.championship_match_id is not null)
execute function private.sync_game_to_championship();

-- ---------------------------------------------------------------------------
-- Mata-mata: o vencedor avança (venha o placar do organizador ou do time)
-- ---------------------------------------------------------------------------

create or replace function private.advance_knockout()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  winner uuid;
  next_id uuid;
begin
  if new.stage <> 'knockout'
     or (new.home_score is not distinct from old.home_score
         and new.away_score is not distinct from old.away_score
         and new.home_penalties is not distinct from old.home_penalties
         and new.away_penalties is not distinct from old.away_penalties) then
    return new;
  end if;

  winner := case
    when new.home_score is null then null
    when new.home_score > new.away_score then new.home_id
    when new.away_score > new.home_score then new.away_id
    when new.home_penalties is null or new.away_penalties is null
      or new.home_penalties = new.away_penalties then null
    when new.home_penalties > new.away_penalties then new.home_id
    else new.away_id
  end;

  select id into next_id from public.championship_matches
  where championship_id = new.championship_id
    and stage = 'knockout'
    and round = new.round + 1
    and slot = new.slot / 2;

  if next_id is null then
    -- A final: com vencedor, o campeonato acaba.
    update public.championships
    set status = case when winner is null then 'running' else 'finished' end
    where id = new.championship_id and status <> 'draft';
  elsif new.slot % 2 = 0 then
    update public.championship_matches set home_id = winner
    where id = next_id and home_id is distinct from winner;
  else
    update public.championship_matches set away_id = winner
    where id = next_id and away_id is distinct from winner;
  end if;
  return new;
end;
$$;

revoke execute on function private.advance_knockout() from public, anon;

create trigger championship_matches_advance
after update on public.championship_matches
for each row execute function private.advance_knockout();

-- Jogos já marcados antes desta migration ganham o jogo correspondente.
update public.championship_matches
set scheduled_at = scheduled_at
where scheduled_at is not null;
