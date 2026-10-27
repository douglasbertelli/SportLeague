-- Dados dos jogadores por jogo (súmula): quem jogou, gols, assistências,
-- cartões e o craque de cada time. Cada time lança os dados dos próprios
-- atletas, durante e depois do jogo.

create table public.game_player_stats (
  game_id uuid not null references public.games (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  athlete_id uuid not null references public.team_players (id) on delete cascade,
  goals smallint not null default 0 check (goals between 0 and 99),
  assists smallint not null default 0 check (assists between 0 and 99),
  yellow_cards smallint not null default 0 check (yellow_cards between 0 and 2),
  red_card boolean not null default false,
  -- Craque do jogo, escolhido por cada time entre os seus.
  best_player boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (game_id, athlete_id)
);

create unique index game_player_stats_one_best
  on public.game_player_stats (game_id, team_id) where best_player;
create index game_player_stats_team_id on public.game_player_stats (team_id);
create index game_player_stats_athlete_id on public.game_player_stats (athlete_id);

create trigger game_player_stats_set_updated_at
before update on public.game_player_stats
for each row execute function public.set_updated_at();

alter table public.game_player_stats enable row level security;

-- Quem vê o jogo vê a súmula (a RLS de games filtra a subconsulta).
create policy "Quem vê o jogo vê a súmula"
on public.game_player_stats for select
to authenticated
using (exists (select 1 from public.games g where g.id = game_player_stats.game_id));

-- O dono do time lança os dados dos próprios atletas num jogo marcado do
-- time, a partir de uma hora antes do início.
create or replace function private.can_edit_player_stats(
  p_game uuid,
  p_team uuid,
  p_athlete uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_team_owner(p_team, (select auth.uid()))
    and exists (
      select 1 from public.games g
      where g.id = p_game
        and (g.team_id = p_team or g.opponent_team_id = p_team)
        and g.status = 'scheduled'
        and g.scheduled_at <= now() + interval '1 hour'
    )
    and exists (
      select 1 from public.team_players a
      where a.id = p_athlete and a.team_id = p_team
    );
$$;

create policy "Time lança os dados dos seus atletas"
on public.game_player_stats for insert
to authenticated
with check (private.can_edit_player_stats(game_id, team_id, athlete_id));

create policy "Time corrige os dados dos seus atletas"
on public.game_player_stats for update
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())))
with check (private.can_edit_player_stats(game_id, team_id, athlete_id));

create policy "Time tira atleta da súmula"
on public.game_player_stats for delete
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())));

-- Gol lançado no placar ao vivo: soma o gol (e a assistência) de uma vez.
-- Roda como quem chamou: as políticas acima valem.
create or replace function public.add_player_goal(
  p_game uuid,
  p_team uuid,
  p_scorer uuid,
  p_assist uuid default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into public.game_player_stats (game_id, team_id, athlete_id, goals)
  values (p_game, p_team, p_scorer, 1)
  on conflict (game_id, athlete_id)
  do update set goals = public.game_player_stats.goals + 1;

  if p_assist is not null and p_assist <> p_scorer then
    insert into public.game_player_stats (game_id, team_id, athlete_id, assists)
    values (p_game, p_team, p_assist, 1)
    on conflict (game_id, athlete_id)
    do update set assists = public.game_player_stats.assists + 1;
  end if;
end;
$$;

-- Totais de cada atleta do time (perfil do atleta e artilharia no perfil do
-- time, que é público). Só jogos marcados contam.
create or replace function public.team_player_totals(p_team uuid)
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
      where g.id = s.game_id and g.status = 'scheduled'
    )
  where a.team_id = p_team
  group by a.id
  order by a.name;
$$;

revoke execute on function public.add_player_goal(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function public.add_player_goal(uuid, uuid, uuid, uuid) to authenticated;
revoke execute on function public.team_player_totals(uuid) from public, anon;
grant execute on function public.team_player_totals(uuid) to authenticated;
revoke execute on function private.can_edit_player_stats(uuid, uuid, uuid) from public, anon;
grant execute on function private.can_edit_player_stats(uuid, uuid, uuid) to authenticated;
