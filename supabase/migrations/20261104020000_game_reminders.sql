-- Lembretes automáticos dos jogos marcados, de 10 em 10 minutos (pg_cron):
--   * "Jogo amanhã" (ou "hoje"), entre 20 e 24 horas antes, só para jogos
--     marcados com mais de um dia de antecedência (os de última hora já
--     tiveram o aviso de jogo marcado);
--   * "Jogo daqui a pouco", entre 1 e 2 horas antes.
-- Recebem o dono, os técnicos e os atletas com conta de cada time da
-- plataforma no jogo. O atleta que ainda não respondeu a presença recebe o
-- lembrete com Sim / Não / Talvez (tipo 'presence'); quem respondeu Não não
-- é lembrado. Viram push como as outras notificações.

create extension if not exists pg_cron with schema pg_catalog;

-- Lembretes já enviados. A data do jogo faz parte da chave: remarcado, o
-- jogo ganha lembretes novos.
create table private.game_reminders (
  game_id uuid not null references public.games (id) on delete cascade,
  kind text not null check (kind in ('day', 'soon')),
  scheduled_at timestamptz not null,
  sent_at timestamptz not null default now(),
  primary key (game_id, kind, scheduled_at)
);

create or replace function private.send_game_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  g record;
  team uuid;
  rival text;
  title text;
  place text;
  base text;
  person record;
  sent integer := 0;
begin
  for g in
    select games.*, k.kind
    from public.games
    cross join (values ('day'), ('soon')) as k (kind)
    where games.status = 'scheduled'
      and (
        (k.kind = 'day'
          and games.scheduled_at > now() + interval '20 hours'
          and games.scheduled_at <= now() + interval '24 hours'
          and games.created_at < games.scheduled_at - interval '24 hours')
        or (k.kind = 'soon'
          and games.scheduled_at > now() + interval '1 hour'
          and games.scheduled_at <= now() + interval '2 hours')
      )
      and not exists (
        select 1 from private.game_reminders r
        where r.game_id = games.id
          and r.kind = k.kind
          and r.scheduled_at = games.scheduled_at
      )
  loop
    insert into private.game_reminders (game_id, kind, scheduled_at)
    values (g.id, g.kind, g.scheduled_at);

    title := case
      when g.kind = 'soon' then 'Jogo daqui a pouco'
      when (g.scheduled_at at time zone 'America/Sao_Paulo')::date
        = (now() at time zone 'America/Sao_Paulo')::date then 'Jogo hoje'
      else 'Jogo amanhã'
    end;
    place := coalesce(
      (select name from public.venues where id = g.venue_id),
      g.location
    );

    foreach team in array array_remove(array[g.team_id, g.opponent_team_id], null)
    loop
      rival := case
        when team = g.team_id then coalesce(
          (select name from public.teams where id = g.opponent_team_id),
          (select name from public.guest_teams where id = g.opponent_guest_id),
          g.opponent, 'o adversário')
        else private.team_name(g.team_id)
      end;
      base := private.team_name(team) || ' x ' || rival || ' às '
        || to_char(g.scheduled_at at time zone 'America/Sao_Paulo', 'HH24:MI')
        || coalesce(' · ' || place, '') || '.';

      for person in
        -- Uma linha por pessoa; quem também é atleta fica com a de atleta.
        select distinct on (people.profile_id) people.*
        from (
          -- Dono e técnicos.
          select private.team_owner(team) as profile_id, null::text as answer,
                 false as athlete
          union all
          select c.profile_id, null, false
          from public.team_coaches c where c.team_id = team
          union all
          -- Atletas com conta, com a resposta da presença (se houver).
          select a.profile_id, p.answer, true
          from public.team_players a
          left join public.game_presence p
            on p.game_id = g.id and p.athlete_id = a.id
          where a.team_id = team and a.profile_id is not null
        ) people
        order by people.profile_id, people.athlete desc
      loop
        continue when person.profile_id is null or person.answer = 'no';
        if person.athlete and person.answer is null then
          -- Ainda sem resposta: o lembrete já pergunta (Sim / Não / Talvez).
          perform private.notify(
            person.profile_id, 'presence', title, base || ' Você vai?',
            team, g.id, null, true
          );
        else
          perform private.notify(
            person.profile_id, 'reminder', title, base,
            team, g.id, null, true
          );
        end if;
        sent := sent + 1;
      end loop;
    end loop;
  end loop;
  return sent;
end;
$$;

revoke execute on function private.send_game_reminders()
  from public, anon, authenticated;

select cron.schedule(
  'game-reminders',
  '*/10 * * * *',
  $$select private.send_game_reminders()$$
);
