-- Avisos do campeonato: uma vez por pessoa (quem está nos dois times, ou
-- em dois times inscritos, recebia o mesmo aviso repetido) e com o nome do
-- campeonato no título ("Copa do Bairro" / "Jogo marcado: A x B em …").

create or replace function private.notify_championship_started()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  person record;
begin
  if old.status <> 'draft' or new.status <> 'running' then
    return new;
  end if;
  for person in
    select distinct on (people.profile_id) people.profile_id, people.team_id
    from (
      select private.team_people(ct.team_id) as profile_id, ct.team_id
      from public.championship_teams ct
      where ct.championship_id = new.id
        and ct.team_id is not null
        and ct.status = 'accepted'
    ) people
  loop
    perform private.notify_championship(
      person.profile_id, 'championship_started', new.name,
      'O campeonato começou: a tabela saiu. Veja os jogos do time.',
      person.team_id, new.id
    );
  end loop;
  return new;
end;
$$;

create or replace function private.notify_championship_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
  home public.championship_teams;
  away public.championship_teams;
  kind text;
  body text;
  person record;
begin
  if new.home_id is null or new.away_id is null then
    return new;
  end if;
  if new.home_score is not null
     and (old.home_score is distinct from new.home_score
       or old.away_score is distinct from new.away_score
       or old.home_penalties is distinct from new.home_penalties
       or old.away_penalties is distinct from new.away_penalties) then
    kind := 'championship_result';
  elsif new.scheduled_at is not null
     and old.scheduled_at is distinct from new.scheduled_at then
    kind := 'championship_match';
  else
    return new;
  end if;

  select * into c from public.championships where id = new.championship_id;
  select * into home from public.championship_teams where id = new.home_id;
  select * into away from public.championship_teams where id = new.away_id;

  if kind = 'championship_result' then
    body := 'Resultado: ' || home.name || ' ' || new.home_score || ' x '
      || new.away_score || ' ' || away.name
      || case when new.home_penalties is null then ''
         else ' (pênaltis ' || new.home_penalties || ' x ' || new.away_penalties || ')'
         end || '.';
  else
    body := 'Jogo marcado: ' || home.name || ' x ' || away.name || ' em '
      || private.game_when(new.scheduled_at)
      || coalesce(' · ' || (select name from public.venues where id = new.venue_id), '')
      || '.';
  end if;

  for person in
    select distinct on (people.profile_id) people.profile_id, people.team_id
    from (
      select private.team_people(t) as profile_id, t as team_id
      from unnest(array_remove(array[home.team_id, away.team_id], null)) as t
    ) people
  loop
    perform private.notify_championship(
      person.profile_id, kind, c.name, body, person.team_id, c.id
    );
  end loop;
  return new;
end;
$$;

-- O convite e a resposta também com o nome do campeonato no título.
create or replace function private.notify_championship_team()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
begin
  select * into c from public.championships where id = new.championship_id;
  if tg_op = 'INSERT' and new.status = 'invited' then
    perform private.notify_championship(
      private.team_owner(new.team_id), 'championship_invite', c.name,
      'Convite: o ' || new.name || ' foi chamado para o campeonato. '
        || 'Aceite ou recuse.',
      new.team_id, c.id
    );
  elsif tg_op = 'UPDATE' and old.status = 'invited' and new.status <> 'invited' then
    perform private.notify_championship(
      c.owner_id, 'championship_answer', c.name,
      'O ' || new.name
        || case when new.status = 'accepted' then ' aceitou' else ' recusou' end
        || ' o convite para o campeonato.',
      new.team_id, c.id
    );
  end if;
  return new;
end;
$$;
