-- Perfil público do time: seguidores, placar e estatísticas.
--
-- 1. Um time segue outro (o botão Seguir age pelo time ativo do
--    administrador). Seguidores = times que seguem; seguindo = times seguidos.
-- 2. O placar é lançado por quem marcou, depois do jogo, num amistoso marcado
--    (não pendente nem cancelado), com os dois números juntos.
-- 3. team_profile_stats() devolve os números e os últimos resultados de
--    qualquer time, sem expor os jogos (que só os dois times veem).

create table public.team_follows (
  follower_team_id uuid not null references public.teams (id) on delete cascade,
  followed_team_id uuid not null references public.teams (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_team_id, followed_team_id),
  check (follower_team_id <> followed_team_id)
);

create index team_follows_followed_idx on public.team_follows (followed_team_id);

alter table public.team_follows enable row level security;

create policy "Seguidores visíveis para usuários autenticados"
on public.team_follows for select
to authenticated
using (true);

create policy "Dono do time segue outro time"
on public.team_follows for insert
to authenticated
with check (
  private.is_team_owner(team_follows.follower_team_id, (select auth.uid()))
);

create policy "Dono do time deixa de seguir"
on public.team_follows for delete
to authenticated
using (
  private.is_team_owner(team_follows.follower_team_id, (select auth.uid()))
);

-- Placar: os dois juntos, não negativos, só num amistoso marcado que já
-- aconteceu. A regra de quem pode alterar o jogo (só quem marcou) continua
-- no games_check_status.
create or replace function public.check_game_score()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.team_score is not distinct from old.team_score
     and new.opponent_score is not distinct from old.opponent_score then
    return new;
  end if;
  if (new.team_score is null) <> (new.opponent_score is null) then
    raise exception 'both scores are required';
  end if;
  if new.team_score < 0 or new.opponent_score < 0 then
    raise exception 'scores cannot be negative';
  end if;
  if new.team_score is not null
     and (new.status <> 'scheduled' or new.scheduled_at > now()) then
    raise exception 'score only after a scheduled game';
  end if;
  return new;
end;
$$;

create trigger games_check_score
before update on public.games
for each row execute function public.check_game_score();

-- Números e últimos resultados de um time, do ponto de vista dele.
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
      case when g.team_id = p_team then g.host_is_home else not g.host_is_home end as is_home
    from public.games g
    left join public.teams h on h.id = g.team_id
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
        select scheduled_at, opponent, is_home, goals_for, goals_against
        from played
        order by scheduled_at desc
        limit 5
      ) r
    ), '[]'::jsonb),
    'upcoming', coalesce((
      select jsonb_agg(u order by u.scheduled_at)
      from (
        select scheduled_at, opponent, is_home
        from mine
        where status = 'scheduled' and scheduled_at > now()
        order by scheduled_at
        limit 3
      ) u
    ), '[]'::jsonb)
  );
$$;

revoke execute on function public.team_profile_stats(uuid) from public, anon;
grant execute on function public.team_profile_stats(uuid) to authenticated;
