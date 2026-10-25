-- Perfil do time: os últimos resultados e os próximos jogos trazem também o
-- logo do adversário (nulo para time fictício ou sem logo).

create or replace function public.team_profile_stats(p_team uuid)
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
      case when g.team_id = p_team then g.team_score else g.opponent_score end as goals_for,
      case when g.team_id = p_team then g.opponent_score else g.team_score end as goals_against,
      case when g.team_id = p_team then g.opponent else coalesce(h.name, 'Time') end as opponent,
      case when g.team_id = p_team then o.logo_url else h.logo_url end as opponent_logo_url,
      case when g.team_id = p_team then g.host_is_home else not g.host_is_home end as is_home
    from public.games g
    left join public.teams h on h.id = g.team_id
    left join public.teams o on o.id = g.opponent_team_id
    where g.team_id = p_team or g.opponent_team_id = p_team
  ),
  played as (
    select * from mine where status = 'scheduled' and scheduled_at <= now()
  ),
  scored as (
    select * from played where goals_for is not null
  )
  select jsonb_build_object(
    'played', (select count(*) from played),
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
        select scheduled_at, opponent, opponent_logo_url, is_home
        from mine
        where status = 'scheduled' and scheduled_at > now()
        order by scheduled_at
        limit 3
      ) u
    ), '[]'::jsonb)
  );
$$;
