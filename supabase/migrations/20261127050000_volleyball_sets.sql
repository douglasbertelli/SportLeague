-- Vôlei no banco (Etapa 2 da Fase 2 do multiesporte,
-- docs/multiesporte-fase2-volei.md): modalidades, súmula e placar em sets.
--
-- Tudo aditivo. No vôlei, `team_score` / `opponent_score` (jogo) e
-- `home_score` / `away_score` (jogo de campeonato) passam a ser os sets
-- vencidos, calculados a partir de `set_scores`; o que já usa esses números
-- (vitória, classificação, avanço do mata-mata) continua certo. No futebol,
-- `best_of` e `set_scores` ficam nulos e nada muda.

-- 1. Modalidades e estatísticas do vôlei.
insert into public.sport_modalities (modality, sport) values
  ('volleyball_indoor', 'volleyball'),
  ('volleyball_beach', 'volleyball');

insert into public.sport_stat_defs (sport, key, kind, max_value, sort) values
  ('volleyball', 'points', 'count', 99, 1),
  ('volleyball', 'aces', 'count', 99, 2),
  ('volleyball', 'blocks', 'count', 99, 3);

-- 2. Regras de sets por modalidade (as mesmas do app e do site).
create table public.modality_set_rules (
  modality public.team_modality primary key,
  points_per_set smallint not null check (points_per_set between 1 and 99),
  tie_break_points smallint not null check (tie_break_points between 1 and 99),
  min_lead smallint not null default 2 check (min_lead between 1 and 9),
  default_best_of smallint not null check (default_best_of in (3, 5))
);

insert into public.modality_set_rules
  (modality, points_per_set, tie_break_points, min_lead, default_best_of)
values
  ('volleyball_indoor', 25, 15, 2, 5),
  ('volleyball_beach', 21, 15, 2, 3);

alter table public.modality_set_rules enable row level security;

create policy "Todos veem as regras de sets"
on public.modality_set_rules for select
to anon, authenticated
using (true);

-- 3. Colunas novas.
alter table public.games
  add column best_of smallint check (best_of in (3, 5)),
  add column set_scores jsonb check (set_scores is null or jsonb_typeof(set_scores) = 'array');

alter table public.championships
  add column best_of smallint check (best_of in (3, 5));

alter table public.championship_matches
  add column set_scores jsonb check (set_scores is null or jsonb_typeof(set_scores) = 'array');

-- 4. Confere os sets e devolve os sets vencidos de cada lado ([a, b]).
-- Cada set é [a, b]; todos terminados (alguém chegou ao alvo com a
-- diferença mínima; passando do alvo, só com a diferença exata), o último
-- possível é o tie-break, e não há set depois de alguém ter vencido. A
-- partida pode estar em andamento (ninguém venceu ainda).
create or replace function private.sets_result(
  p_modality public.team_modality,
  p_best_of smallint,
  p_sets jsonb
)
returns int[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.modality_set_rules;
  v_to_win int;
  v_won_a int := 0;
  v_won_b int := 0;
  v_number int := 0;
  v_set jsonb;
  v_a int;
  v_b int;
  v_target int;
  v_high int;
  v_lead int;
begin
  select * into r from public.modality_set_rules where modality = p_modality;
  if not found then
    raise exception 'sets_not_for_modality' using errcode = '22023';
  end if;
  if p_best_of is null or p_best_of not in (3, 5) then
    raise exception 'sets_invalid' using errcode = '22023';
  end if;
  if p_sets is null then
    return null;
  end if;
  v_to_win := p_best_of / 2 + 1;

  for v_set in select value from jsonb_array_elements(p_sets) loop
    v_number := v_number + 1;
    if v_won_a = v_to_win or v_won_b = v_to_win or v_number > p_best_of
       or jsonb_typeof(v_set) <> 'array' or jsonb_array_length(v_set) <> 2
       or jsonb_typeof(v_set -> 0) <> 'number'
       or jsonb_typeof(v_set -> 1) <> 'number' then
      raise exception 'sets_invalid' using errcode = '22023';
    end if;
    -- Inteiros de 0 a 99 (o cast de "25.5" para int falharia com outra
    -- mensagem; a comparação abaixo recusa antes).
    if (v_set ->> 0)::numeric <> trunc((v_set ->> 0)::numeric)
       or (v_set ->> 1)::numeric <> trunc((v_set ->> 1)::numeric)
       or (v_set ->> 0)::numeric not between 0 and 99
       or (v_set ->> 1)::numeric not between 0 and 99 then
      raise exception 'sets_invalid' using errcode = '22023';
    end if;
    v_a := (v_set ->> 0)::int;
    v_b := (v_set ->> 1)::int;
    v_target := case when v_number = p_best_of then r.tie_break_points
                     else r.points_per_set end;
    v_high := greatest(v_a, v_b);
    v_lead := abs(v_a - v_b);
    if v_high < v_target or v_lead < r.min_lead
       or (v_high > v_target and v_lead <> r.min_lead) then
      raise exception 'sets_invalid' using errcode = '22023';
    end if;
    if v_a > v_b then
      v_won_a := v_won_a + 1;
    else
      v_won_b := v_won_b + 1;
    end if;
  end loop;

  return array[v_won_a, v_won_b];
end;
$$;
revoke execute on function private.sets_result(public.team_modality, smallint, jsonb) from public, anon;
grant execute on function private.sets_result(public.team_modality, smallint, jsonb) to authenticated;

-- [a, b] -> [b, a] em cada set (a visão do outro time).
create or replace function private.flip_sets(p_sets jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_sets is null then null else coalesce(
    (select jsonb_agg(jsonb_build_array(e -> 1, e -> 0) order by ord)
       from jsonb_array_elements(p_sets) with ordinality as t(e, ord)),
    '[]'::jsonb
  ) end;
$$;
revoke execute on function private.flip_sets(jsonb) from public, anon;
grant execute on function private.flip_sets(jsonb) to authenticated;

-- 5. Jogos: no vôlei, melhor de (padrão da modalidade) e placar pelos sets;
-- no futebol, sem sets. Roda antes de games_check_score (ordem alfabética
-- dos gatilhos), que continua conferindo o horário do placar.
create or replace function private.apply_game_sets()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sport public.sport_type;
  v_result int[];
begin
  select sm.sport into v_sport
    from public.sport_modalities sm where sm.modality = new.modality;

  if v_sport is distinct from 'volleyball' then
    if new.best_of is not null or new.set_scores is not null then
      raise exception 'sets_not_for_sport' using errcode = '22023';
    end if;
    return new;
  end if;

  if new.best_of is null then
    select default_best_of into new.best_of
      from public.modality_set_rules where modality = new.modality;
  end if;
  v_result := private.sets_result(new.modality, new.best_of, new.set_scores);
  if v_result is null then
    -- Sem sets lançados: sem placar.
    if new.team_score is not null or new.opponent_score is not null then
      raise exception 'sets_required' using errcode = '22023';
    end if;
  else
    new.team_score := v_result[1];
    new.opponent_score := v_result[2];
  end if;
  return new;
end;
$$;
revoke execute on function private.apply_game_sets() from public, anon, authenticated;

create trigger games_apply_sets
before insert or update of modality, best_of, set_scores, team_score, opponent_score
on public.games
for each row execute function private.apply_game_sets();

-- 6. Campeonatos: melhor de só no vôlei (padrão da modalidade).
create or replace function private.apply_championship_best_of()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sport public.sport_type;
begin
  select sm.sport into v_sport
    from public.sport_modalities sm where sm.modality = new.modality;
  if v_sport is distinct from 'volleyball' then
    if new.best_of is not null then
      raise exception 'sets_not_for_sport' using errcode = '22023';
    end if;
  elsif new.best_of is null then
    select default_best_of into new.best_of
      from public.modality_set_rules where modality = new.modality;
  end if;
  return new;
end;
$$;
revoke execute on function private.apply_championship_best_of() from public, anon, authenticated;

create trigger championships_apply_best_of
before insert or update of modality, best_of on public.championships
for each row execute function private.apply_championship_best_of();

-- 7. Jogos de campeonato: no vôlei, placar pelos sets e sem pênaltis.
create or replace function private.apply_match_sets()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
  v_sport public.sport_type;
  v_result int[];
begin
  select * into c from public.championships where id = new.championship_id;
  select sm.sport into v_sport
    from public.sport_modalities sm where sm.modality = c.modality;

  if v_sport is distinct from 'volleyball' then
    if new.set_scores is not null then
      raise exception 'sets_not_for_sport' using errcode = '22023';
    end if;
    return new;
  end if;

  if new.home_penalties is not null or new.away_penalties is not null then
    raise exception 'sets_no_penalties' using errcode = '22023';
  end if;
  v_result := private.sets_result(c.modality, c.best_of, new.set_scores);
  if v_result is null then
    if new.home_score is not null or new.away_score is not null then
      raise exception 'sets_required' using errcode = '22023';
    end if;
  else
    new.home_score := v_result[1];
    new.away_score := v_result[2];
  end if;
  return new;
end;
$$;
revoke execute on function private.apply_match_sets() from public, anon, authenticated;

create trigger championship_matches_apply_sets
before insert or update of set_scores, home_score, away_score, home_penalties, away_penalties
on public.championship_matches
for each row execute function private.apply_match_sets();

-- 8. O time do jogo de campeonato também lança os sets (como o placar).
create or replace function private.check_championship_game()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  editable constant text[] := array[
    'team_score', 'opponent_score', 'set_scores', 'match_phase',
    'clock_started_at', 'clock_elapsed', 'period_minutes', 'updated_at'
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

-- 9. Sincronia jogo de campeonato -> jogo do time: leva o melhor de e os
-- sets (na visão do time do jogo).
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
  host_sets jsonb;
begin
  select id into game_id from public.games where championship_match_id = new.id;

  if new.home_id is not null and new.away_id is not null then
    select * into home from public.championship_teams where id = new.home_id;
    select * into away from public.championship_teams where id = new.away_id;
  end if;

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
  host_sets := case when home_side then new.set_scores
                    else private.flip_sets(new.set_scores) end;

  if game_id is null then
    insert into public.games (
      team_id, opponent, scheduled_at, type, modality, opponent_team_id,
      opponent_guest_id, host_is_home, venue_id, team_score, opponent_score,
      championship_match_id, best_of, set_scores
    ) values (
      host.team_id, rival.name, new.scheduled_at, 'championship', c.modality,
      rival.team_id, rival.guest_team_id, home_side, new.venue_id,
      host_score, rival_score, new.id, c.best_of, host_sets
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
      opponent_score = rival_score,
      best_of = c.best_of,
      set_scores = host_sets
    where id = game_id
      and (team_id, opponent, scheduled_at, opponent_team_id, opponent_guest_id,
           host_is_home, venue_id, team_score, opponent_score, best_of,
           set_scores)
          is distinct from
          (host.team_id, rival.name, new.scheduled_at, rival.team_id,
           rival.guest_team_id, home_side, new.venue_id, host_score,
           rival_score, c.best_of, host_sets);
  end if;
  return new;
end;
$$;

-- 10. Sincronia jogo do time -> jogo de campeonato: o placar e os sets (na
-- visão de mandante e visitante).
create or replace function private.sync_game_to_championship()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_trigger_depth() > 1
     or (new.team_score is not distinct from old.team_score
         and new.opponent_score is not distinct from old.opponent_score
         and new.set_scores is not distinct from old.set_scores) then
    return new;
  end if;
  update public.championship_matches set
    home_score = case when new.host_is_home then new.team_score else new.opponent_score end,
    away_score = case when new.host_is_home then new.opponent_score else new.team_score end,
    set_scores = case when new.host_is_home then new.set_scores
                      else private.flip_sets(new.set_scores) end,
    home_penalties = null,
    away_penalties = null
  where id = new.championship_match_id;
  return new;
end;
$$;
