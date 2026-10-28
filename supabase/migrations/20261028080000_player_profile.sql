-- Perfil do jogador: dados de atleta (a data de nascimento já existia) e os
-- números dele em todos os times em que está vinculado.

alter table public.profiles
  add column preferred_position text check (char_length(preferred_position) between 1 and 40),
  add column preferred_foot text check (preferred_foot in ('right', 'left', 'both')),
  add column height_cm smallint check (height_cm between 100 and 230),
  add constraint profiles_birth_date_check
    check (birth_date >= date '1900-01-01');

-- Totais do usuário logado em cada time em que é atleta; com p_from e p_to,
-- só os jogos da temporada.
create function public.my_player_totals(
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns table (
  athlete_id uuid,
  team_id uuid,
  team_name text,
  team_logo_url text,
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
    count(*) filter (where s.best_player)
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
grant execute on function public.my_player_totals(timestamptz, timestamptz) to authenticated;
