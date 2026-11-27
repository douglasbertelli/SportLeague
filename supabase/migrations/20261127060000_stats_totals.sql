-- Totais pela súmula genérica (Etapa 3 da Fase 2 do multiesporte,
-- docs/multiesporte-fase2-volei.md).
--
-- As funções de totais passam a devolver também `stats` (a soma, chave por
-- chave, de `game_player_stats.stats`), sem tirar nada do que devolvem hoje:
-- é o que permite mostrar os números do vôlei (pontos, aces, bloqueios), que
-- não têm coluna própria. Os jogos ganham os sets (`set_scores`) e o perfil
-- do time ganha os pontos dentro dos sets (`points_for` / `points_against`,
-- 0 no futebol). Para o futebol, os campos de hoje continuam iguais.

-- 1. Soma de objetos jsonb, chave por chave ({"goals": 1} + {"goals": 2,
-- "assists": 1} = {"goals": 3, "assists": 1}). Valores que não são número
-- ficam de fora; nulo conta como {}.
create or replace function private.jsonb_sum_step(p_acc jsonb, p_value jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_acc, '{}'::jsonb) || coalesce(
    (select jsonb_object_agg(
        e.key,
        coalesce((p_acc ->> e.key)::numeric, 0) + (e.value #>> '{}')::numeric)
       from jsonb_each(coalesce(p_value, '{}'::jsonb)) as e
      where jsonb_typeof(e.value) = 'number'),
    '{}'::jsonb);
$$;

create aggregate private.jsonb_sum(jsonb) (
  sfunc = private.jsonb_sum_step,
  stype = jsonb,
  initcond = '{}'
);

-- Soma dos pontos de cada lado em [[a, b], …] (os sets do vôlei).
create or replace function private.set_points(p_sets jsonb, p_side int)
returns int
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum((e ->> p_side)::int), 0)::int
    from jsonb_array_elements(coalesce(p_sets, '[]'::jsonb)) as e;
$$;

-- 2. Totais dos atletas do time (perfil do atleta e rankings do time).
drop function public.team_player_totals(uuid, timestamptz, timestamptz);
create function public.team_player_totals(
  p_team uuid,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns table(
  athlete_id uuid, name text, jersey_number smallint, "position" text,
  games bigint, goals bigint, assists bigint, yellow_cards bigint,
  red_cards bigint, best_player bigint, stats jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    coalesce(p.nickname, p.full_name, a.name),
    a.jersey_number,
    a.position,
    count(s.game_id),
    coalesce(sum(s.goals), 0),
    coalesce(sum(s.assists), 0),
    coalesce(sum(s.yellow_cards), 0),
    count(*) filter (where s.red_card),
    count(*) filter (where s.best_player),
    private.jsonb_sum(s.stats)
  from public.team_players a
  left join public.profiles p on p.id = a.profile_id
  left join public.game_player_stats s on s.athlete_id = a.id
    and exists (
      select 1 from public.games g
      where g.id = s.game_id
        and g.status = 'scheduled'
        and (p_from is null or g.scheduled_at >= p_from)
        and (p_to is null or g.scheduled_at < p_to)
    )
  where a.team_id = p_team
  group by a.id, p.nickname, p.full_name
  order by 2;
$$;
revoke execute on function public.team_player_totals(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.team_player_totals(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- 3. Totais do jogador logado em cada time (Meus números).
drop function public.my_player_totals(timestamptz, timestamptz);
create function public.my_player_totals(
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns table(
  athlete_id uuid, team_id uuid, team_name text, team_logo_url text,
  jersey_number smallint, "position" text, games bigint, goals bigint,
  assists bigint, yellow_cards bigint, red_cards bigint, best_player bigint,
  stats jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    t.id,
    t.name,
    t.logo_url,
    a.jersey_number,
    a.position,
    count(s.game_id),
    coalesce(sum(s.goals), 0),
    coalesce(sum(s.assists), 0),
    coalesce(sum(s.yellow_cards), 0),
    count(*) filter (where s.red_card),
    count(*) filter (where s.best_player),
    private.jsonb_sum(s.stats)
  from public.team_players a
  join public.teams t on t.id = a.team_id
  left join public.game_player_stats s on s.athlete_id = a.id
    and exists (
      select 1 from public.games g
      where g.id = s.game_id
        and g.status = 'scheduled'
        and (p_from is null or g.scheduled_at >= p_from)
        and (p_to is null or g.scheduled_at < p_to)
    )
  where a.profile_id = (select auth.uid())
  group by a.id, t.id
  order by t.name;
$$;
revoke execute on function public.my_player_totals(timestamptz, timestamptz) from public, anon;
grant execute on function public.my_player_totals(timestamptz, timestamptz) to authenticated, service_role;

-- 4. Totais dos atletas no campeonato (artilharia do campeonato).
drop function public.championship_player_totals(uuid);
create function public.championship_player_totals(p_championship uuid)
returns table(
  athlete_id uuid, name text, team_name text, logo_url text, goals integer,
  assists integer, games integer, best_player integer, stats jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    coalesce(pr.nickname, pr.full_name, a.name),
    t.name,
    t.logo_url,
    sum(s.goals)::integer,
    sum(s.assists)::integer,
    count(*)::integer,
    count(*) filter (where s.best_player)::integer,
    private.jsonb_sum(s.stats)
  from public.championship_matches m
  join public.games g on g.championship_match_id = m.id
  join public.game_player_stats s on s.game_id = g.id
  join public.team_players a on a.id = s.athlete_id
  left join public.profiles pr on pr.id = a.profile_id
  join public.teams t on t.id = s.team_id
  where m.championship_id = p_championship
    and private.can_see_championship(p_championship, (select auth.uid()))
  group by a.id, pr.nickname, pr.full_name, a.name, t.name, t.logo_url;
$$;
revoke execute on function public.championship_player_totals(uuid) from public, anon;
grant execute on function public.championship_player_totals(uuid) to authenticated, service_role;

-- 5. Perfil do time: os sets dos últimos jogos e os pontos dentro dos sets.
create or replace function public.team_profile_stats(
  p_team uuid,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with mine as (
    select
      g.scheduled_at,
      g.status,
      g.modality,
      g.location,
      to_jsonb(v) as venue,
      case when g.team_id = p_team then g.team_score else g.opponent_score end as goals_for,
      case when g.team_id = p_team then g.opponent_score else g.team_score end as goals_against,
      case when g.team_id = p_team then g.set_scores
           else private.flip_sets(g.set_scores) end as set_scores,
      case when g.team_id = p_team then g.opponent else coalesce(h.name, 'Time') end as opponent,
      case when g.team_id = p_team then g.opponent_team_id else g.team_id end as opponent_team_id,
      case when g.team_id = p_team then o.logo_url else h.logo_url end as opponent_logo_url,
      case when g.team_id = p_team then g.host_is_home else not g.host_is_home end as is_home
    from public.games g
    left join public.teams h on h.id = g.team_id
    left join public.teams o on o.id = g.opponent_team_id
    left join public.venues v on v.id = g.venue_id
    where g.team_id = p_team or g.opponent_team_id = p_team
  ),
  played as (
    select * from mine where status = 'scheduled' and scheduled_at <= now()
  ),
  -- Os números da temporada.
  season as (
    select * from played
    where (p_from is null or scheduled_at >= p_from)
      and (p_to is null or scheduled_at < p_to)
  ),
  scored as (
    select * from season where goals_for is not null
  )
  select jsonb_build_object(
    'played', (select count(*) from season),
    'wins', (select count(*) from scored where goals_for > goals_against),
    'draws', (select count(*) from scored where goals_for = goals_against),
    'losses', (select count(*) from scored where goals_for < goals_against),
    'goals_for', (select coalesce(sum(goals_for), 0) from scored),
    'goals_against', (select coalesce(sum(goals_against), 0) from scored),
    -- Vôlei: pontos dentro dos sets (no futebol, 0).
    'points_for', (select coalesce(sum(private.set_points(set_scores, 0)), 0) from scored),
    'points_against', (select coalesce(sum(private.set_points(set_scores, 1)), 0) from scored),
    'followers', (select count(*) from public.team_follows f where f.followed_team_id = p_team),
    'following', (select count(*) from public.team_follows f where f.follower_team_id = p_team),
    'recent', coalesce((
      select jsonb_agg(r order by r.scheduled_at desc)
      from (
        select scheduled_at, opponent, opponent_logo_url, is_home, goals_for, goals_against, set_scores
        from played
        order by scheduled_at desc
        limit 5
      ) r
    ), '[]'::jsonb),
    'upcoming', coalesce((
      select jsonb_agg(u order by u.scheduled_at)
      from (
        select scheduled_at, opponent, opponent_team_id, opponent_logo_url,
               is_home, modality, location, venue
        from mine
        where status = 'scheduled' and scheduled_at > now()
        order by scheduled_at
        limit 3
      ) u
    ), '[]'::jsonb)
  );
$$;

-- 6. Estatísticas do campeonato: os jogadores ganham `stats`.
create or replace function private.championship_stats_data(p_championship uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with games as (
    select g.id as game_id, m.id as match_id, m.stage, m.round, m.slot, m.home_id, m.away_id, m.home_score, m.away_score
    from public.championship_matches m join public.games g on g.championship_match_id = m.id
    where m.championship_id = p_championship
  ),
  stats as (
    select s.*, gm.match_id, gm.stage, gm.round, coalesce(nullif(pr.nickname, ''), tp.name) as display, t.name as team_name, t.logo_url
    from games gm
    join public.game_player_stats s on s.game_id = gm.game_id
    join public.team_players tp on tp.id = s.athlete_id
    left join public.profiles pr on pr.id = tp.profile_id
    join public.teams t on t.id = s.team_id
  ),
  players as (
    select athlete_id, display as name, team_name, logo_url,
           sum(goals)::int as goals, sum(assists)::int as assists,
           sum(case when red_card and yellow_cards = 2 then 0 else yellow_cards end)::int as yellow_cards,
           (count(*) filter (where red_card))::int as red_cards,
           (count(*) filter (where best_player))::int as best_player,
           count(*)::int as games,
           private.jsonb_sum(stats.stats) as stats
    from stats group by athlete_id, display, team_name, logo_url
  ),
  played as (
    select * from public.championship_matches where championship_id = p_championship and home_score is not null
  ),
  team_rows as (
    select ct.id, ct.name, coalesce(t.logo_url, ct.logo_url) as logo_url,
           (select count(*) from played p where p.home_id = ct.id or p.away_id = ct.id)::int as played,
           coalesce((select sum(case when p.home_id = ct.id then p.home_score else p.away_score end) from played p where p.home_id = ct.id or p.away_id = ct.id), 0)::int as goals_for,
           coalesce((select sum(case when p.home_id = ct.id then p.away_score else p.home_score end) from played p where p.home_id = ct.id or p.away_id = ct.id), 0)::int as goals_against,
           coalesce((select sum(case when s.red_card and s.yellow_cards = 2 then 0 else s.yellow_cards end) from stats s where s.team_id = ct.team_id), 0)::int as yellow_cards,
           coalesce((select count(*) from stats s where s.team_id = ct.team_id and s.red_card), 0)::int as red_cards
    from public.championship_teams ct
    left join public.teams t on t.id = ct.team_id
    where ct.championship_id = p_championship and ct.status = 'accepted'
  ),
  best as (
    select stage, round, match_id, display as name, team_name, logo_url, goals, assists,
           row_number() over (partition by stage, round order by goals desc, assists desc, display) as rank
    from stats where best_player
  ),
  rounds as (
    select stage, round,
           jsonb_agg(jsonb_build_object('name', name, 'team_name', team_name, 'logo_url', logo_url,
                                        'goals', goals, 'assists', assists, 'top', rank = 1) order by rank) as players
    from best group by stage, round
  )
  select jsonb_build_object(
    'players', coalesce((select jsonb_agg(to_jsonb(p) - 'athlete_id' order by p.goals desc, p.assists desc, p.name) from players p), '[]'::jsonb),
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'name', r.name, 'logo_url', r.logo_url, 'played', r.played,
        'goals_for', r.goals_for, 'goals_against', r.goals_against,
        'yellow_cards', r.yellow_cards, 'red_cards', r.red_cards,
        'fair_play', r.yellow_cards + 3 * r.red_cards) order by r.name) from team_rows r), '[]'::jsonb),
    'suspended', coalesce((select jsonb_agg(jsonb_build_object('name', x.name, 'team_name', x.team_name, 'reason', x.reason) order by x.team_name, x.name)
      from private.championship_cards(p_championship) x where x.suspended), '[]'::jsonb),
    'rounds', coalesce((select jsonb_agg(jsonb_build_object('stage', stage, 'round', round, 'players', players) order by stage desc, round desc) from rounds), '[]'::jsonb),
    'yellow_limit', (select yellow_limit from public.championships where id = p_championship),
    'red_games', (select red_games from public.championships where id = p_championship)
  );
$$;

-- 7. Campeonato público: o melhor de, os sets dos jogos e `stats` dos
-- jogadores.
create or replace function public.public_championship(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with c as (
    select * from public.championships where public_slug = p_slug and public_enabled
  ),
  entries as (
    select ct.id, ct.name, ct.status, ct.group_label, coalesce(t.logo_url, ct.logo_url) as logo_url,
           ct.guest_team_id is not null as guest, ct.created_at
    from public.championship_teams ct join c on c.id = ct.championship_id
    left join public.teams t on t.id = ct.team_id
    where ct.status <> 'declined'
  ),
  matches as (
    select m.id, m.stage, m.round, m.slot, m.group_label, m.home_id, m.away_id, m.scheduled_at,
           m.home_score, m.away_score, m.home_penalties, m.away_penalties, m.set_scores,
           v.name as venue_name, v.city as venue_city, v.state as venue_state,
           private.public_match_live(m.id) as live
    from public.championship_matches m join c on c.id = m.championship_id
    left join public.venues v on v.id = m.venue_id
  ),
  players as (
    select coalesce(nullif(pr.nickname, ''), a.name) as name, t.name as team_name, t.logo_url,
           sum(s.goals)::integer as goals, sum(s.assists)::integer as assists, count(*)::integer as games,
           (count(*) filter (where s.best_player))::integer as best_player,
           private.jsonb_sum(s.stats) as stats
    from c
    join public.championship_matches m on m.championship_id = c.id
    join public.games g on g.championship_match_id = m.id
    join public.game_player_stats s on s.game_id = g.id
    join public.team_players a on a.id = s.athlete_id
    left join public.profiles pr on pr.id = a.profile_id
    join public.teams t on t.id = s.team_id
    group by a.id, pr.nickname, a.name, t.name, t.logo_url
  )
  select case when not exists (select 1 from c) then null else jsonb_build_object(
    'championship', (select jsonb_build_object(
        'id', id, 'name', name, 'modality', modality, 'format', format, 'double_round', double_round,
        'group_count', group_count, 'qualifiers_per_group', qualifiers_per_group, 'team_count', team_count,
        'group_size', group_size, 'knockout_fill', knockout_fill, 'knockout_qualifiers', knockout_qualifiers,
        'status', status, 'created_at', created_at, 'best_of', best_of,
        'signup_code', case when signup_enabled and status = 'draft' then signup_code end) from c),
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'name', e.name, 'status', e.status, 'group_label', e.group_label,
        'logo_url', e.logo_url, 'guest', e.guest,
        'players', (select r.players from public.championship_requests r where r.entry_id = e.id and r.status = 'accepted' limit 1)
      ) order by e.created_at) from entries e), '[]'::jsonb),
    'matches', coalesce((select jsonb_agg(to_jsonb(m) order by m.stage, m.round, m.slot) from matches m), '[]'::jsonb),
    'players', coalesce((select jsonb_agg(to_jsonb(p) order by p.goals desc, p.name) from players p), '[]'::jsonb),
    'stats', private.championship_stats_data((select id from c))
  ) end;
$$;

-- 8. Perfil público do jogador: `stats` nos totais, na carreira, por time e
-- nos últimos jogos (com os sets).
create or replace function public.public_profile(
  p_slug text,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with me as (
    select p.*
    from public.profiles p
    where (p.public_slug = p_slug or p.public_handle = lower(p_slug))
      and p.public_enabled
      and p.deleted_at is null
    order by (p.public_slug = p_slug) desc
    limit 1
  ),
  athletes as (
    select a.id, a.team_id, a.jersey_number, a.position, a.inactive_at
    from public.team_players a
    join me on me.id = a.profile_id
    join public.teams t on t.id = a.team_id and t.inactive_at is null
  ),
  stats as (
    select s.*, g.scheduled_at
    from public.game_player_stats s
    join athletes a on a.id = s.athlete_id
    join public.games g on g.id = s.game_id
    where g.status = 'scheduled' and g.scheduled_at <= now()
  ),
  season_stats as (
    select * from stats
    where (p_from is null or scheduled_at >= p_from)
      and (p_to is null or scheduled_at < p_to)
  ),
  teams as (
    select t.id, t.name, t.logo_url, t.city, t.state, 'admin' as relation, null::smallint as jersey_number, null::text as position
    from public.teams t join me on me.id = t.owner_id
    where t.inactive_at is null
    union all
    select t.id, t.name, t.logo_url, t.city, t.state, 'coach', null, null
    from public.team_coaches c
    join me on me.id = c.profile_id
    join public.teams t on t.id = c.team_id and t.inactive_at is null
    union all
    select t.id, t.name, t.logo_url, t.city, t.state, 'player', a.jersey_number, a.position
    from athletes a join public.teams t on t.id = a.team_id
    where a.inactive_at is null
  ),
  totals as (
    select
      count(*) as games,
      coalesce(sum(goals), 0) as goals,
      coalesce(sum(assists), 0) as assists,
      coalesce(sum(yellow_cards), 0) as yellow_cards,
      count(*) filter (where red_card) as red_cards,
      count(*) filter (where best_player) as best_player,
      private.jsonb_sum(season_stats.stats) as stats
    from season_stats
  ),
  career as (
    select
      count(*) as games,
      coalesce(sum(goals), 0) as goals,
      coalesce(sum(assists), 0) as assists,
      count(*) filter (where best_player) as best_player,
      private.jsonb_sum(stats.stats) as stats
    from stats
  )
  select case when not exists (select 1 from me) then null else jsonb_build_object(
    'name', (select coalesce(nullif(nickname, ''), full_name) from me),
    'full_name', (select full_name from me),
    'role', (select role from me),
    'age', (select extract(year from age(birth_date))::int from me where birth_date is not null),
    'position', (select preferred_position from me),
    'foot', (select preferred_foot from me),
    'height_cm', (select height_cm from me),
    'avatar_url', (select avatar_url from me),
    'cover_url', (select cover_url from me),
    'member_since', (select created_at from me),
    'teams', coalesce((select jsonb_agg(t order by t.relation, t.name) from teams t), '[]'::jsonb),
    'totals', (select to_jsonb(t) from totals t),
    'career', (select to_jsonb(c) from career c),
    'by_team', coalesce((
      select jsonb_agg(x order by x.games desc, x.team_name)
      from (
        select t.id as team_id, t.name as team_name, t.logo_url as team_logo_url,
               count(s.game_id) as games,
               coalesce(sum(s.goals), 0) as goals,
               coalesce(sum(s.assists), 0) as assists,
               coalesce(sum(s.yellow_cards), 0) as yellow_cards,
               count(*) filter (where s.red_card) as red_cards,
               count(*) filter (where s.best_player) as best_player,
               private.jsonb_sum(s.stats) as stats
        from athletes a
        join public.teams t on t.id = a.team_id
        left join season_stats s on s.athlete_id = a.id
        group by t.id
      ) x
    ), '[]'::jsonb),
    'recent', coalesce((
      select jsonb_agg(r order by r.scheduled_at desc)
      from (
        select g.scheduled_at, s.goals, s.assists, s.best_player, s.yellow_cards, s.red_card,
               s.stats,
               t.name as team_name, t.logo_url as team_logo_url,
               case when g.team_id = s.team_id then g.opponent else coalesce(h.name, 'Time') end as opponent,
               case when g.team_id = s.team_id then o.logo_url else h.logo_url end as opponent_logo_url,
               case when g.team_id = s.team_id then g.team_score else g.opponent_score end as goals_for,
               case when g.team_id = s.team_id then g.opponent_score else g.team_score end as goals_against,
               case when g.team_id = s.team_id then g.set_scores
                    else private.flip_sets(g.set_scores) end as set_scores
        from season_stats s
        join public.games g on g.id = s.game_id
        join public.teams t on t.id = s.team_id
        left join public.teams h on h.id = g.team_id
        left join public.teams o on o.id = g.opponent_team_id
        order by g.scheduled_at desc
        limit 8
      ) r
    ), '[]'::jsonb),
    'team_records', coalesce((
      select jsonb_agg(
        jsonb_build_object('team_id', t.id, 'team_name', t.name, 'team_logo_url', t.logo_url, 'relation', t.relation)
        || (public.team_profile_stats(t.id, p_from, p_to) - 'upcoming' - 'followers' - 'following')
        order by t.name
      )
      from (select distinct on (id) * from teams where relation in ('admin', 'coach') order by id, relation) t
    ), '[]'::jsonb)
  ) end;
$$;
