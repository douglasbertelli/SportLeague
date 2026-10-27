-- Vaquinha: o time junta dinheiro para um item (bola, colete, uniforme ou
-- outro descrito). O dono do time define o valor por pessoa e marca quem
-- pagou (os atletas e ele mesmo); o técnico e os atletas com conta
-- acompanham. O time pode ter várias vaquinhas, e as antigas são encerradas.

create table public.fundraisers (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  item text not null check (item in ('ball', 'bib', 'kit', 'other')),
  -- Obrigatória em "Outros": o que vai ser comprado.
  description text check (description is null or length(trim(description)) between 1 and 60),
  amount_cents integer not null check (amount_cents > 0),
  closed boolean not null default false,
  created_by uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now(),
  constraint fundraisers_other_needs_description
    check (item <> 'other' or description is not null)
);

create index fundraisers_team_id on public.fundraisers (team_id);

-- Quem pagou: um atleta do time ou o dono (pelo perfil). Sem linha = não pagou.
create table public.fundraiser_payments (
  id uuid primary key default gen_random_uuid(),
  fundraiser_id uuid not null references public.fundraisers (id) on delete cascade,
  athlete_id uuid references public.team_players (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete cascade,
  paid_at timestamptz not null default now(),
  constraint fundraiser_payments_one_payer
    check (num_nonnulls(athlete_id, profile_id) = 1),
  unique (fundraiser_id, athlete_id),
  unique (fundraiser_id, profile_id)
);

create index fundraiser_payments_athlete_id on public.fundraiser_payments (athlete_id);
create index fundraiser_payments_profile_id on public.fundraiser_payments (profile_id);

alter table public.fundraisers enable row level security;
alter table public.fundraiser_payments enable row level security;

-- Dono, técnico ou atleta com conta no time.
create or replace function private.is_team_member(team uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_team_staff(team, uid)
    or exists (
      select 1 from public.team_players p
      where p.team_id = team and p.profile_id = uid
    );
$$;

-- O dono marca e desmarca enquanto a vaquinha está aberta.
create or replace function private.can_edit_payments(p_fundraiser uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.fundraisers f
    join public.teams t on t.id = f.team_id
    where f.id = p_fundraiser
      and not f.closed
      and t.owner_id = (select auth.uid())
  );
$$;

-- O pagamento vale para um atleta do time ou para o dono do time.
create or replace function private.can_mark_payment(
  p_fundraiser uuid,
  p_athlete uuid,
  p_profile uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_edit_payments(p_fundraiser) and exists (
    select 1
    from public.fundraisers f
    join public.teams t on t.id = f.team_id
    where f.id = p_fundraiser
      and (
        (p_athlete is not null and exists (
          select 1 from public.team_players p
          where p.id = p_athlete and p.team_id = f.team_id
        ))
        or (p_profile is not null and p_profile = t.owner_id)
      )
  );
$$;

create or replace function private.fundraiser_team(p_fundraiser uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select team_id from public.fundraisers where id = p_fundraiser;
$$;

revoke execute on function private.is_team_member(uuid, uuid) from public, anon;
grant execute on function private.is_team_member(uuid, uuid) to authenticated;
revoke execute on function private.can_edit_payments(uuid) from public, anon;
grant execute on function private.can_edit_payments(uuid) to authenticated;
revoke execute on function private.can_mark_payment(uuid, uuid, uuid) from public, anon;
grant execute on function private.can_mark_payment(uuid, uuid, uuid) to authenticated;
revoke execute on function private.fundraiser_team(uuid) from public, anon;
grant execute on function private.fundraiser_team(uuid) to authenticated;

create policy "Membros do time veem as vaquinhas"
on public.fundraisers for select
to authenticated
using (private.is_team_member(team_id, (select auth.uid())));

create policy "Dono cria vaquinha"
on public.fundraisers for insert
to authenticated
with check (private.is_team_owner(team_id, (select auth.uid())));

create policy "Dono altera a vaquinha"
on public.fundraisers for update
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())))
with check (private.is_team_owner(team_id, (select auth.uid())));

create policy "Dono remove a vaquinha"
on public.fundraisers for delete
to authenticated
using (private.is_team_owner(team_id, (select auth.uid())));

create policy "Membros do time veem os pagamentos"
on public.fundraiser_payments for select
to authenticated
using (
  private.is_team_member(
    private.fundraiser_team(fundraiser_id),
    (select auth.uid())
  )
);

create policy "Dono marca quem pagou"
on public.fundraiser_payments for insert
to authenticated
with check (private.can_mark_payment(fundraiser_id, athlete_id, profile_id));

create policy "Dono desmarca o pagamento"
on public.fundraiser_payments for delete
to authenticated
using (private.can_edit_payments(fundraiser_id));
