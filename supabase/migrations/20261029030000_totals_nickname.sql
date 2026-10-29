-- Artilharia, garçons e perfil do atleta mostram o apelido do jogador
-- vinculado (o nome do perfil dele); sem apelido, o nome cadastrado no time.
create or replace function public.team_player_totals(
  p_team uuid,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
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
    coalesce(p.nickname, a.name),
    a.jersey_number,
    a.position,
    count(s.game_id),
    coalesce(sum(s.goals), 0),
    coalesce(sum(s.assists), 0),
    coalesce(sum(s.yellow_cards), 0),
    count(*) filter (where s.red_card),
    count(*) filter (where s.best_player)
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
  group by a.id, p.nickname
  order by 2;
$$;
