-- Relógio da partida: quem marcou o jogo inicia, pausa e encerra cada tempo;
-- os dois times veem o mesmo relógio. O tempo corrido do tempo atual é
-- clock_elapsed (segundos acumulados até a última pausa) mais o que passou
-- desde clock_started_at (nulo quando pausado).

create type public.match_phase as enum ('first', 'interval', 'second', 'finished');

alter table public.games
  add column match_phase public.match_phase,
  add column clock_started_at timestamptz,
  add column clock_elapsed integer not null default 0
    check (clock_elapsed >= 0),
  add column period_minutes smallint
    check (period_minutes between 1 and 60);

-- Ações do relógio com a hora do servidor, para os dois aparelhos contarem
-- igual. Roda como quem chamou: as regras de quem altera o jogo (RLS e
-- games_check_status: só quem marcou) continuam valendo.
create or replace function public.game_clock(
  p_game uuid,
  p_action text,
  p_period_minutes integer default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  g public.games;
  running_for integer;
begin
  select * into g from public.games where id = p_game;
  if not found then
    raise exception 'game not found';
  end if;
  if g.status <> 'scheduled' then
    raise exception 'the clock needs a scheduled game';
  end if;
  -- Pode começar até uma hora antes do horário marcado (atraso de relógio,
  -- aquecimento que vira jogo).
  if g.scheduled_at > now() + interval '1 hour' then
    raise exception 'the game has not started yet';
  end if;

  running_for := case
    when g.clock_started_at is null then 0
    else floor(extract(epoch from now() - g.clock_started_at))::integer
  end;

  case p_action
    when 'start' then
      if g.match_phase is not null then
        raise exception 'the game clock already started';
      end if;
      if p_period_minutes is null then
        raise exception 'period minutes are required';
      end if;
      update public.games set
        match_phase = 'first', clock_started_at = now(), clock_elapsed = 0,
        period_minutes = p_period_minutes
      where id = p_game;
    when 'pause' then
      if g.match_phase is null or g.match_phase not in ('first', 'second') or g.clock_started_at is null then
        raise exception 'the clock is not running';
      end if;
      update public.games set
        clock_started_at = null, clock_elapsed = g.clock_elapsed + running_for
      where id = p_game;
    when 'resume' then
      if g.match_phase is null or g.match_phase not in ('first', 'second') or g.clock_started_at is not null then
        raise exception 'the clock is not paused';
      end if;
      update public.games set clock_started_at = now() where id = p_game;
    when 'end_half' then
      if g.match_phase is distinct from 'first' then
        raise exception 'only the first half can end';
      end if;
      update public.games set
        match_phase = 'interval', clock_started_at = null, clock_elapsed = 0
      where id = p_game;
    when 'start_second' then
      if g.match_phase is distinct from 'interval' then
        raise exception 'the second half starts after the interval';
      end if;
      update public.games set
        match_phase = 'second', clock_started_at = now(), clock_elapsed = 0
      where id = p_game;
    when 'finish' then
      if g.match_phase is distinct from 'second' then
        raise exception 'only the second half can finish the game';
      end if;
      update public.games set
        match_phase = 'finished', clock_started_at = null,
        clock_elapsed = g.clock_elapsed + running_for
      where id = p_game;
    when 'reset' then
      update public.games set
        match_phase = null, clock_started_at = null, clock_elapsed = 0
      where id = p_game;
    else
      raise exception 'unknown clock action';
  end case;

  -- Sem linha alterada: a RLS escondeu o jogo de quem não é o dono.
  if not found then
    raise exception 'only the host can control the clock';
  end if;
end;
$$;

revoke execute on function public.game_clock(uuid, text, integer) from public, anon;
grant execute on function public.game_clock(uuid, text, integer) to authenticated;
