-- Presença com três respostas: Sim, Não e Talvez. A coluna `going`
-- (booleana) vira `answer` ('yes', 'no', 'maybe'; nula = sem resposta).

alter table public.game_presence
  add column answer text check (answer in ('yes', 'no', 'maybe'));

update public.game_presence
set answer = case when going then 'yes' else 'no' end
where going is not null;

alter table public.game_presence drop column going;

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

  -- Avisa quem ainda não respondeu (quem disse Talvez já respondeu).
  for athlete in
    select a.profile_id from public.game_presence p
    join public.team_players a on a.id = p.athlete_id
    where p.game_id = p_game and p.team_id = p_team
      and p.answer is null and a.profile_id is not null
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

drop function public.answer_presence(uuid, uuid, boolean);

create or replace function public.answer_presence(
  p_game uuid,
  p_team uuid,
  p_answer text
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
  insert into public.game_presence (game_id, team_id, athlete_id, answer, answered_at)
  values (p_game, p_team, me, p_answer, now())
  on conflict (game_id, athlete_id)
  do update set answer = excluded.answer, answered_at = excluded.answered_at;
end;
$$;

revoke execute on function public.answer_presence(uuid, uuid, text) from public, anon;
grant execute on function public.answer_presence(uuid, uuid, text) to authenticated;
