-- Artilharia e garçons do campeonato: soma a súmula de todos os jogos do
-- campeonato (os que viraram jogo dos times). Cada time só vê a súmula dos
-- próprios jogos; esta função soma todos, para quem pode ver o campeonato.

create or replace function public.championship_player_totals(p_championship uuid)
returns table (
  athlete_id uuid,
  name text,
  team_name text,
  logo_url text,
  goals integer,
  assists integer,
  games integer,
  best_player integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    -- Do jogador com conta, o apelido (ou o nome do perfil); senão, o nome
    -- cadastrado no time.
    coalesce(pr.nickname, pr.full_name, a.name),
    t.name,
    t.logo_url,
    sum(s.goals)::integer,
    sum(s.assists)::integer,
    count(*)::integer,
    count(*) filter (where s.best_player)::integer
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
grant execute on function public.championship_player_totals(uuid) to authenticated;
