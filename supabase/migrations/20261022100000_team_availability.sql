-- Calendário de disponibilidade dos times.
-- Cada disponibilidade é um horário de início de jogo:
--   avulsa:     starts_at                      ("sáb. 25/10 às 15:00")
--   recorrente: weekday + start_time (+ período) ("todo sábado às 15:00")
-- Horários recorrentes são no fuso de Brasília (America/Sao_Paulo).
--
-- Amistoso contra time da plataforma só pode ser marcado num horário livre do
-- adversário; contra time fictício, num horário livre do próprio time. Um
-- horário com amistoso pendente ou marcado daquele time fica ocupado.

create table public.team_availability (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  starts_at timestamptz,
  weekday smallint check (weekday between 1 and 7), -- ISO: 1 = segunda, 7 = domingo
  start_time time,
  starts_on date,
  ends_on date,
  created_at timestamptz not null default now(),
  check (
    (starts_at is not null and weekday is null and start_time is null
      and starts_on is null and ends_on is null)
    or (starts_at is null and weekday is not null and start_time is not null)
  ),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

create index team_availability_team_id_idx on public.team_availability (team_id);
create unique index team_availability_single_uniq
on public.team_availability (team_id, starts_at) where starts_at is not null;
create unique index team_availability_weekly_uniq
on public.team_availability (team_id, weekday, start_time) where weekday is not null;

alter table public.team_availability enable row level security;

-- Os horários são públicos para quem está logado: quem marca o amistoso
-- precisa ver os do adversário.
create policy "Disponibilidade visível para usuários autenticados"
on public.team_availability for select
to authenticated
using (true);

create policy "Dono do time cadastra disponibilidade"
on public.team_availability for insert
to authenticated
with check (private.is_team_owner(team_availability.team_id, (select auth.uid())));

create policy "Dono do time altera disponibilidade"
on public.team_availability for update
to authenticated
using (private.is_team_owner(team_availability.team_id, (select auth.uid())))
with check (private.is_team_owner(team_availability.team_id, (select auth.uid())));

create policy "Dono do time remove disponibilidade"
on public.team_availability for delete
to authenticated
using (private.is_team_owner(team_availability.team_id, (select auth.uid())));

-- Se o time oferece o horário [at] (avulso ou recorrente), sem olhar jogos.
create or replace function private.team_offers_slot(p_team uuid, p_at timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.team_availability a
    where a.team_id = p_team
      and (
        a.starts_at = p_at
        or (
          a.weekday = extract(isodow from (p_at at time zone 'America/Sao_Paulo'))
          and a.start_time = (p_at at time zone 'America/Sao_Paulo')::time
          and (a.starts_on is null or (p_at at time zone 'America/Sao_Paulo')::date >= a.starts_on)
          and (a.ends_on is null or (p_at at time zone 'America/Sao_Paulo')::date <= a.ends_on)
        )
      )
  );
$$;

-- Se o time já tem amistoso pendente ou marcado no horário [at]
-- (ignorando o jogo [p_except], que está sendo editado). Precisa ver os jogos
-- de outros times, por isso roda como definer; só devolve sim/não.
create or replace function private.team_slot_taken(
  p_team uuid,
  p_at timestamptz,
  p_except uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.games g
    where g.status in ('pending', 'scheduled')
      and g.scheduled_at = p_at
      and (g.team_id = p_team or g.opponent_team_id = p_team)
      and (p_except is null or g.id <> p_except)
  );
$$;

revoke execute on function private.team_offers_slot(uuid, timestamptz) from public, anon;
revoke execute on function private.team_slot_taken(uuid, timestamptz, uuid) from public, anon;
grant execute on function private.team_offers_slot(uuid, timestamptz) to authenticated;
grant execute on function private.team_slot_taken(uuid, timestamptz, uuid) to authenticated;

-- Horários livres de um time entre [p_from] e [p_to], já sem os ocupados.
-- Chamada pelo app (rpc). Devolve só os horários, nunca os jogos.
create or replace function public.available_slots(
  p_team uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (starts_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  with candidates as (
    select a.starts_at
    from public.team_availability a
    where a.team_id = p_team
      and a.starts_at is not null
    union
    select ((d.day + a.start_time) at time zone 'America/Sao_Paulo') as starts_at
    from public.team_availability a
    cross join lateral (
      select gs::date as day
      from generate_series(
        (p_from at time zone 'America/Sao_Paulo')::date,
        (p_to at time zone 'America/Sao_Paulo')::date,
        interval '1 day'
      ) gs
    ) d
    where a.team_id = p_team
      and a.weekday is not null
      and extract(isodow from d.day) = a.weekday
      and (a.starts_on is null or d.day >= a.starts_on)
      and (a.ends_on is null or d.day <= a.ends_on)
  )
  select c.starts_at
  from candidates c
  where c.starts_at >= p_from
    and c.starts_at <= p_to
    and not private.team_slot_taken(p_team, c.starts_at)
  order by c.starts_at;
$$;

revoke execute on function public.available_slots(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.available_slots(uuid, timestamptz, timestamptz) to authenticated;

-- Regra ao marcar: o horário precisa estar livre no calendário do adversário
-- (time da plataforma) ou do próprio time (adversário fictício). Conferido ao
-- marcar e quando quem marcou muda a data ou o adversário; jogos antigos
-- continuam editáveis sem mudar a data, e a exclusão de times não é barrada.
create or replace function public.check_game_slot()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  calendar_team uuid;
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.scheduled_at is not distinct from old.scheduled_at
     and (new.opponent_team_id is null
          or new.opponent_team_id is not distinct from old.opponent_team_id)
     and (new.opponent_guest_id is null
          or new.opponent_guest_id is not distinct from old.opponent_guest_id) then
    return new;
  end if;

  calendar_team := coalesce(new.opponent_team_id, new.team_id);
  if not private.team_offers_slot(calendar_team, new.scheduled_at) then
    raise exception 'time slot not available in the calendar';
  end if;
  if private.team_slot_taken(calendar_team, new.scheduled_at, new.id) then
    raise exception 'time slot already taken';
  end if;
  return new;
end;
$$;

create trigger games_check_slot
before insert or update on public.games
for each row execute function public.check_game_slot();
