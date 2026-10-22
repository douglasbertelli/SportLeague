-- Amistosos com adversário escolhido e na mesma modalidade.
-- O adversário é um time da plataforma ou um time fictício do administrador
-- (salvo para reutilizar). O jogo tem a modalidade e os dois times precisam
-- jogá-la. O tipo continua no banco, mas o app só marca amistosos.

-- =========================================================
-- Times fictícios: adversários que não estão na plataforma.
-- Visíveis e editáveis só pelo administrador que os criou.
-- =========================================================
create table public.guest_teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  modality public.team_modality not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index guest_teams_owner_id_idx on public.guest_teams (owner_id);

create trigger guest_teams_set_updated_at
before update on public.guest_teams
for each row execute function public.set_updated_at();

alter table public.guest_teams enable row level security;

create policy "Administrador vê os próprios times fictícios"
on public.guest_teams for select
to authenticated
using ((select auth.uid()) = owner_id);

create policy "Administrador cria times fictícios"
on public.guest_teams for insert
to authenticated
with check (
  (select auth.uid()) = owner_id and private.is_admin((select auth.uid()))
);

create policy "Administrador edita os próprios times fictícios"
on public.guest_teams for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy "Administrador remove os próprios times fictícios"
on public.guest_teams for delete
to authenticated
using ((select auth.uid()) = owner_id);

-- =========================================================
-- Jogo: modalidade e adversário
-- opponent continua com o nome do adversário (mantido se o time for excluído).
-- =========================================================
alter table public.games
  add column modality public.team_modality,
  add column opponent_team_id uuid references public.teams (id) on delete set null,
  add column opponent_guest_id uuid references public.guest_teams (id) on delete set null,
  add constraint games_one_opponent check (
    opponent_team_id is null or opponent_guest_id is null
  ),
  add constraint games_not_against_itself check (opponent_team_id <> team_id);

create index games_opponent_team_id_idx on public.games (opponent_team_id);
create index games_opponent_guest_id_idx on public.games (opponent_guest_id);

-- Os dois times precisam jogar a modalidade do jogo. Conferido ao marcar e
-- quando a modalidade muda ou um novo adversário é escolhido. Jogos antigos sem
-- modalidade continuam editáveis até ela ser definida, e o adversário pode
-- ficar vazio quando o time dele é excluído (on delete set null).
create or replace function public.check_game_modality()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and new.modality is not distinct from old.modality
     and (new.opponent_team_id is null
          or new.opponent_team_id is not distinct from old.opponent_team_id)
     and (new.opponent_guest_id is null
          or new.opponent_guest_id is not distinct from old.opponent_guest_id) then
    return new;
  end if;

  if new.modality is null then
    raise exception 'game modality is required';
  end if;
  if new.opponent_team_id is null and new.opponent_guest_id is null then
    raise exception 'game opponent is required';
  end if;

  if not exists (
    select 1 from public.teams t
    where t.id = new.team_id and new.modality = any (t.modalities)
  ) then
    raise exception 'team does not play this modality';
  end if;

  if new.opponent_team_id is not null and not exists (
    select 1 from public.teams t
    where t.id = new.opponent_team_id and new.modality = any (t.modalities)
  ) then
    raise exception 'opponent does not play this modality';
  end if;

  if new.opponent_guest_id is not null and not exists (
    select 1 from public.guest_teams g
    join public.teams t on t.id = new.team_id
    where g.id = new.opponent_guest_id
      and g.owner_id = t.owner_id
      and g.modality = new.modality
  ) then
    raise exception 'opponent does not play this modality';
  end if;

  return new;
end;
$$;

create trigger games_check_modality
before insert or update on public.games
for each row execute function public.check_game_modality();
