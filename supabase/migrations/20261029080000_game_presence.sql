-- Confirmação de presença nos jogos marcados. O dono ou o técnico pede (os
-- atletas com conta recebem a notificação); cada atleta responde Vou / Não
-- vou até o jogo começar. A escrita é só pelas funções abaixo.

create table public.game_presence (
  game_id uuid not null references public.games (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  athlete_id uuid not null references public.team_players (id) on delete cascade,
  going boolean,
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (game_id, athlete_id)
);

create index game_presence_team_id on public.game_presence (team_id);
create index game_presence_athlete_id on public.game_presence (athlete_id);

alter table public.game_presence enable row level security;

create policy "Equipe do time e o próprio atleta veem a presença"
on public.game_presence for select
to authenticated
using (
  private.is_team_staff(team_id, (select auth.uid()))
  or exists (
    select 1 from public.team_players a
    where a.id = game_presence.athlete_id
      and a.profile_id = (select auth.uid())
  )
);

-- Jogo marcado do time que ainda não começou.
create or replace function private.presence_open(p_game uuid, p_team uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.games g
    where g.id = p_game
      and (g.team_id = p_team or g.opponent_team_id = p_team)
      and g.status = 'scheduled'
      and g.scheduled_at > now()
  );
$$;

-- O dono ou o técnico pede a confirmação: avisa os atletas com conta que
-- ainda não responderam. Devolve quantos foram avisados.
create or replace function public.request_presence(p_game uuid, p_team uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  g public.games;
  rival text;
  athlete record;
  sent integer := 0;
begin
  if not private.is_team_staff(p_team, (select auth.uid())) then
    raise exception 'only the team staff can ask for presence';
  end if;
  if not private.presence_open(p_game, p_team) then
    raise exception 'game not open for presence';
  end if;
  select * into g from public.games where id = p_game;
  rival := case
    when g.team_id = p_team then coalesce(
      (select name from public.teams where id = g.opponent_team_id),
      (select name from public.guest_teams where id = g.opponent_guest_id),
      g.opponent, 'o adversário')
    else private.team_name(g.team_id)
  end;

  insert into public.game_presence (game_id, team_id, athlete_id)
  select p_game, p_team, a.id from public.team_players a
  where a.team_id = p_team and a.profile_id is not null
  on conflict (game_id, athlete_id) do nothing;

  for athlete in
    select a.profile_id from public.game_presence p
    join public.team_players a on a.id = p.athlete_id
    where p.game_id = p_game and p.team_id = p_team
      and p.going is null and a.profile_id is not null
  loop
    perform private.notify(
      athlete.profile_id, 'presence', 'Confirme sua presença',
      'O ' || private.team_name(p_team) || ' joga contra ' || rival || ' em '
        || private.game_when(g.scheduled_at) || '. Você vai?',
      p_team, p_game, null, true
    );
    sent := sent + 1;
  end loop;
  return sent;
end;
$$;

-- O atleta responde (e pode mudar até o jogo começar).
create or replace function public.answer_presence(
  p_game uuid,
  p_team uuid,
  p_going boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid;
begin
  select id into me from public.team_players
  where team_id = p_team and profile_id = (select auth.uid());
  if me is null then
    raise exception 'not an athlete of this team';
  end if;
  if not private.presence_open(p_game, p_team) then
    raise exception 'game not open for presence';
  end if;
  insert into public.game_presence (game_id, team_id, athlete_id, going, answered_at)
  values (p_game, p_team, me, p_going, now())
  on conflict (game_id, athlete_id)
  do update set going = excluded.going, answered_at = excluded.answered_at;
end;
$$;

revoke execute on function private.presence_open(uuid, uuid) from public, anon;
grant execute on function private.presence_open(uuid, uuid) to authenticated;
revoke execute on function public.request_presence(uuid, uuid) from public, anon;
grant execute on function public.request_presence(uuid, uuid) to authenticated;
revoke execute on function public.answer_presence(uuid, uuid, boolean) from public, anon;
grant execute on function public.answer_presence(uuid, uuid, boolean) to authenticated;
