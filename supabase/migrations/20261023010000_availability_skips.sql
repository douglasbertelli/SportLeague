-- Imprevistos: o time pode tirar um dia de um horário recorrente ("neste
-- sábado não dá") sem apagar as outras semanas. O dia pulado deixa de ser
-- oferecido e não aceita amistoso novo; amistosos já marcados continuam.

create table public.team_availability_skips (
  availability_id uuid not null references public.team_availability (id) on delete cascade,
  on_date date not null,
  created_at timestamptz not null default now(),
  primary key (availability_id, on_date)
);

alter table public.team_availability_skips enable row level security;

-- Dono do time do horário recorrente [p_availability].
create or replace function private.is_availability_owner(p_availability uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.team_availability a
    join public.teams t on t.id = a.team_id
    where a.id = p_availability
      and a.weekday is not null
      and t.owner_id = p_user
  );
$$;

revoke execute on function private.is_availability_owner(uuid, uuid) from public, anon;
grant execute on function private.is_availability_owner(uuid, uuid) to authenticated;

create policy "Dias pulados visíveis para usuários autenticados"
on public.team_availability_skips for select
to authenticated
using (true);

create policy "Dono do time pula um dia"
on public.team_availability_skips for insert
to authenticated
with check (
  private.is_availability_owner(team_availability_skips.availability_id, (select auth.uid()))
);

create policy "Dono do time devolve um dia"
on public.team_availability_skips for delete
to authenticated
using (
  private.is_availability_owner(team_availability_skips.availability_id, (select auth.uid()))
);

-- Mesmas funções da 20261022100000_team_availability, agora sem os dias pulados.
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
          and not exists (
            select 1 from public.team_availability_skips s
            where s.availability_id = a.id
              and s.on_date = (p_at at time zone 'America/Sao_Paulo')::date
          )
        )
      )
  );
$$;

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
      and not exists (
        select 1 from public.team_availability_skips s
        where s.availability_id = a.id
          and s.on_date = d.day
      )
  )
  select c.starts_at
  from candidates c
  where c.starts_at >= p_from
    and c.starts_at <= p_to
    and not private.team_slot_taken(p_team, c.starts_at)
  order by c.starts_at;
$$;
