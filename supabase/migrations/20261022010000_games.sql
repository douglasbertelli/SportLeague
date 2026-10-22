-- Jogos de cada time (amistosos e campeonatos).
-- O adversário é só um nome por enquanto; o placar é preenchido depois do jogo.

create type public.game_type as enum ('friendly', 'championship');

create table public.games (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  opponent text not null check (char_length(opponent) between 2 and 80),
  scheduled_at timestamptz not null,
  location text check (char_length(location) <= 160),
  type public.game_type not null default 'friendly',
  team_score smallint check (team_score between 0 and 999),
  opponent_score smallint check (opponent_score between 0 and 999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Placar completo ou nenhum.
  check ((team_score is null) = (opponent_score is null))
);

create index games_team_id_scheduled_at_idx on public.games (team_id, scheduled_at);

create trigger games_set_updated_at
before update on public.games
for each row execute function public.set_updated_at();

alter table public.games enable row level security;

-- Os jogos são exclusivos do time: só o dono e os atletas do time veem.
create policy "Dono e atletas do time veem os jogos"
on public.games for select
to authenticated
using (
  private.is_team_owner(team_id, (select auth.uid()))
  or exists (
    select 1 from public.team_players p
    where p.team_id = games.team_id and p.profile_id = (select auth.uid())
  )
);

create policy "Dono do time cadastra jogos"
on public.games for insert
to authenticated
with check (private.is_team_owner(team_id, (select auth.uid())));

create policy "Dono do time atualiza jogos"
on public.games for update
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())))
with check (private.is_team_owner(team_id, (select auth.uid())));

create policy "Dono do time remove jogos"
on public.games for delete
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())));
