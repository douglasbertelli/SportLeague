-- Temporada nas estatísticas: os números do time e dos atletas passam a
-- aceitar um período [p_from, p_to) (ano inteiro ou um mês). Sem período,
-- contam todos os jogos, como antes. Últimos resultados, próximos jogos e
-- seguidores não mudam com o período.

drop function public.team_profile_stats(uuid);
drop function public.team_player_totals(uuid);

create function public.team_profile_stats(
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
    'followers', (select count(*) from public.team_follows f where f.followed_team_id = p_team),
    'following', (select count(*) from public.team_follows f where f.follower_team_id = p_team),
    'recent', coalesce((
      select jsonb_agg(r order by r.scheduled_at desc)
      from (
        select scheduled_at, opponent, opponent_logo_url, is_home, goals_for, goals_against
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

create function public.team_player_totals(
  p_team uuid,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns table (
  athlete_id uuid,
  name text,
  jersey_number smallint,
  "position" text,
  games bigint,
  goals bigint,
  assists bigint,
  yellow_cards bigint,
  red_cards bigint,
  best_player bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    a.name,
    a.jersey_number,
    a.position,
    count(s.game_id),
    coalesce(sum(s.goals), 0),
    coalesce(sum(s.assists), 0),
    coalesce(sum(s.yellow_cards), 0),
    count(*) filter (where s.red_card),
    count(*) filter (where s.best_player)
  from public.team_players a
  left join public.game_player_stats s on s.athlete_id = a.id
    and exists (
      select 1 from public.games g
      where g.id = s.game_id
        and g.status = 'scheduled'
        and (p_from is null or g.scheduled_at >= p_from)
        and (p_to is null or g.scheduled_at < p_to)
    )
  where a.team_id = p_team
  group by a.id
  order by a.name;
$$;

revoke execute on function public.team_profile_stats(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.team_profile_stats(uuid, timestamptz, timestamptz) to authenticated;
revoke execute on function public.team_player_totals(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.team_player_totals(uuid, timestamptz, timestamptz) to authenticated;
