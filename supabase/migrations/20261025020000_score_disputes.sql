-- Contestação do placar: depois do jogo, o adversário (time da plataforma)
-- diz qual foi o placar na visão dele e o motivo; quem marcou o jogo aceita
-- (o placar muda) ou mantém o dele. Os placares ficam do ponto de vista de
-- quem marcou, como em games.

create table public.score_disputes (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  -- Time que contestou (o adversário do jogo).
  team_id uuid not null references public.teams (id) on delete cascade,
  team_score smallint not null check (team_score between 0 and 99),
  opponent_score smallint not null check (opponent_score between 0 and 99),
  message text not null check (char_length(btrim(message)) between 1 and 500),
  status text not null default 'open'
    check (status in ('open', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- Uma contestação aberta por jogo.
create unique index score_disputes_one_open
  on public.score_disputes (game_id) where status = 'open';
create index score_disputes_team_id on public.score_disputes (team_id);

alter table public.score_disputes enable row level security;

-- Quem marcou o jogo e quem contestou veem.
create policy "Os dois times veem a contestação"
on public.score_disputes for select
to authenticated
using (
  private.is_team_owner(team_id, (select auth.uid()))
  or exists (
    select 1 from public.games g
    where g.id = score_disputes.game_id
      and private.is_team_owner(g.team_id, (select auth.uid()))
  )
);

-- O adversário contesta um jogo que já terminou e tem placar.
create policy "Adversário contesta o placar"
on public.score_disputes for insert
to authenticated
with check (
  status = 'open'
  and resolved_at is null
  and private.is_team_owner(team_id, (select auth.uid()))
  and exists (
    select 1 from public.games g
    where g.id = score_disputes.game_id
      and g.opponent_team_id = score_disputes.team_id
      and g.status = 'scheduled'
      and g.team_score is not null
      and (g.match_phase = 'finished'
           or (g.match_phase is null and g.scheduled_at + interval '2 hours' <= now()))
  )
);

-- Quem marcou responde: aceita (o placar do jogo passa a ser o contestado)
-- ou mantém o dele. Roda como quem chamou: só o dono do jogo altera o placar.
create or replace function public.resolve_score_dispute(
  p_dispute uuid,
  p_accept boolean
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  d public.score_disputes;
begin
  select * into d from public.score_disputes where id = p_dispute;
  if not found or d.status <> 'open' then
    raise exception 'dispute not open';
  end if;
  if not exists (
    select 1 from public.games g
    where g.id = d.game_id
      and private.is_team_owner(g.team_id, (select auth.uid()))
  ) then
    raise exception 'only the host can answer the dispute';
  end if;

  if p_accept then
    update public.games
    set team_score = d.team_score, opponent_score = d.opponent_score
    where id = d.game_id;
  end if;
  update public.score_disputes
  set status = case when p_accept then 'accepted' else 'rejected' end,
      resolved_at = now()
  where id = p_dispute;
end;
$$;

-- Quem marcou responde (pela função acima): só a situação muda, e só uma vez.
create policy "Quem marcou responde à contestação"
on public.score_disputes for update
to authenticated
using (
  status = 'open'
  and exists (
    select 1 from public.games g
    where g.id = score_disputes.game_id
      and private.is_team_owner(g.team_id, (select auth.uid()))
  )
)
with check (status in ('accepted', 'rejected'));

revoke update on public.score_disputes from authenticated, anon;
grant update (status, resolved_at) on public.score_disputes to authenticated;

revoke execute on function public.resolve_score_dispute(uuid, boolean) from public, anon;
grant execute on function public.resolve_score_dispute(uuid, boolean) to authenticated;
