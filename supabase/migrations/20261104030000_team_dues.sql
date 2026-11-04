-- Mensalidade do time. O dono do time define o valor por mês, o dia do
-- vencimento e (opcional) a chave PIX, e marca, mês a mês, quais atletas
-- pagaram. O técnico e os atletas com conta acompanham. Os atletas com conta
-- que não pagaram recebem lembrete no dia do vencimento e, se continuar em
-- aberto, 3 dias depois.

create table public.team_dues (
  team_id uuid primary key references public.teams (id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  due_day smallint not null check (due_day between 1 and 28),
  pix_key text check (pix_key is null or length(trim(pix_key)) between 1 and 120),
  -- Primeiro mês cobrado (dia 1); os anteriores não aparecem.
  start_month date not null default date_trunc(
    'month', now() at time zone 'America/Sao_Paulo'
  )::date check (extract(day from start_month) = 1),
  created_at timestamptz not null default now()
);

-- Quem pagou cada mês (dia 1 do mês). Sem linha = em aberto.
create table public.team_due_payments (
  team_id uuid not null references public.teams (id) on delete cascade,
  athlete_id uuid not null references public.team_players (id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  paid_at timestamptz not null default now(),
  primary key (athlete_id, month)
);

create index team_due_payments_team_month
  on public.team_due_payments (team_id, month);

alter table public.team_dues enable row level security;
alter table public.team_due_payments enable row level security;

create policy "Membros do time veem a mensalidade"
on public.team_dues for select
to authenticated
using (private.is_team_member(team_id, (select auth.uid())));

create policy "Dono configura a mensalidade"
on public.team_dues for insert
to authenticated
with check (private.is_team_owner(team_id, (select auth.uid())));

create policy "Dono altera a mensalidade"
on public.team_dues for update
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())))
with check (private.is_team_owner(team_id, (select auth.uid())));

create policy "Dono remove a mensalidade"
on public.team_dues for delete
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())));

create policy "Membros do time veem os pagamentos da mensalidade"
on public.team_due_payments for select
to authenticated
using (private.is_team_member(team_id, (select auth.uid())));

-- O dono marca um atleta do próprio time.
create policy "Dono marca a mensalidade paga"
on public.team_due_payments for insert
to authenticated
with check (
  private.is_team_owner(team_id, (select auth.uid()))
  and exists (
    select 1 from public.team_players p
    where p.id = athlete_id and p.team_id = team_due_payments.team_id
  )
);

create policy "Dono desmarca a mensalidade"
on public.team_due_payments for delete
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())));

-- ---------------------------------------------------------------------------
-- Lembretes (todo dia às 9h de Brasília, pelo pg_cron)
-- ---------------------------------------------------------------------------

create table private.dues_reminders (
  athlete_id uuid not null references public.team_players (id) on delete cascade,
  month date not null,
  kind text not null check (kind in ('due', 'late')),
  sent_at timestamptz not null default now(),
  primary key (athlete_id, month, kind)
);

create or replace function private.send_dues_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  today date := (now() at time zone 'America/Sao_Paulo')::date;
  this_month date := date_trunc('month', today)::date;
  month_name text := (array[
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
    'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ])[extract(month from today)::int];
  d record;
  athlete record;
  reminder_kind text;
  amount text;
  sent integer := 0;
begin
  for d in
    select * from public.team_dues
    where start_month <= this_month
      and today in (this_month + due_day - 1, this_month + due_day + 2)
  loop
    reminder_kind := case
      when today = this_month + d.due_day - 1 then 'due'
      else 'late'
    end;
    -- "1,250.00" -> "R$ 1.250,00" (troca os separadores).
    amount := 'R$ ' || translate(
      to_char(d.amount_cents / 100.0, 'FM999,999,990.00'), ',.', '.,'
    );

    for athlete in
      select a.id, a.profile_id
      from public.team_players a
      where a.team_id = d.team_id
        and a.profile_id is not null
        and not exists (
          select 1 from public.team_due_payments p
          where p.athlete_id = a.id and p.month = this_month
        )
        and not exists (
          select 1 from private.dues_reminders r
          where r.athlete_id = a.id and r.month = this_month and r.kind = reminder_kind
        )
    loop
      insert into private.dues_reminders (athlete_id, month, kind)
      values (athlete.id, this_month, reminder_kind);
      perform private.notify(
        athlete.profile_id,
        'dues',
        case reminder_kind
          when 'due' then 'Mensalidade vence hoje'
          else 'Mensalidade em atraso'
        end,
        'Mensalidade de ' || month_name || ' do ' || private.team_name(d.team_id)
          || ': ' || amount || '.'
          || case when d.pix_key is null then ''
             else ' PIX: ' || d.pix_key end,
        d.team_id, null, null, true
      );
      sent := sent + 1;
    end loop;
  end loop;
  return sent;
end;
$$;

revoke execute on function private.send_dues_reminders()
  from public, anon, authenticated;

select cron.schedule(
  'dues-reminders',
  '0 12 * * *',
  $$select private.send_dues_reminders()$$
);
