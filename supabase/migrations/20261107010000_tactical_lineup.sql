-- Escalação no campo (Premium): o time escolhe a formação do jogo e cada
-- titular ganha a posição no campo. O administrador escolhe, no time, se a
-- escalação abre em lista (padrão) ou no campo.

-- Posição do titular na formação (0 = goleiro); nulo na lista e na reserva.
alter table public.game_lineups
  add column slot smallint check (slot between 0 and 10);

-- Formação do time no jogo.
create table public.game_formations (
  game_id uuid not null references public.games (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  formation text not null check (formation ~ '^[0-9](-[0-9]){1,4}$'),
  updated_at timestamptz not null default now(),
  primary key (game_id, team_id)
);

create index game_formations_team_id on public.game_formations (team_id);

alter table public.game_formations enable row level security;

-- O time pode mexer: dono ou técnico, no jogo do time, antes de acabar.
create or replace function private.can_edit_formation(p_game uuid, p_team uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_team_staff(p_team, (select auth.uid()))
    and exists (
      select 1 from public.games g
      where g.id = p_game
        and (g.team_id = p_team or g.opponent_team_id = p_team)
        and g.status in ('pending', 'scheduled')
    );
$$;

revoke execute on function private.can_edit_formation(uuid, uuid) from public, anon;
grant execute on function private.can_edit_formation(uuid, uuid) to authenticated;

create policy "Quem vê o jogo vê a formação"
on public.game_formations for select
to authenticated
using (exists (select 1 from public.games g where g.id = game_formations.game_id));

create policy "Dono ou técnico escolhe a formação"
on public.game_formations for insert
to authenticated
with check (private.can_edit_formation(game_id, team_id));

create policy "Dono ou técnico muda a formação"
on public.game_formations for update
to authenticated
using (private.is_team_staff(team_id, (select auth.uid())))
with check (private.can_edit_formation(game_id, team_id));

create policy "Dono ou técnico tira a formação"
on public.game_formations for delete
to authenticated
using (private.is_team_staff(team_id, (select auth.uid())));

-- Como a escalação abre no time: lista (padrão) ou campo.
alter table public.teams
  add column lineup_style text not null default 'list'
    check (lineup_style in ('list', 'field'));

-- ---------------------------------------------------------------------------
-- Premium
-- ---------------------------------------------------------------------------

insert into public.plan_features (plan, feature, quota, description) values
  ('free', 'tactical_lineup', 0, null),
  ('premium', 'tactical_lineup', null,
   'Monte a escalação no campo: escolha a formação e arraste os jogadores '
   || 'para as posições.');

-- O recurso vale pelo plano do dono do time (o técnico não tem plano).
create or replace function public.team_has_feature(p_team uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_feature(private.team_owner(p_team), p_feature);
$$;

revoke execute on function public.team_has_feature(uuid, text) from public, anon;
grant execute on function public.team_has_feature(uuid, text) to authenticated;

create or replace function private.check_tactical_lineup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_feature(
    private.team_owner(new.team_id), 'tactical_lineup'
  );
  return new;
end;
$$;

create trigger game_formations_check_plan
before insert or update on public.game_formations
for each row execute function private.check_tactical_lineup();

create trigger game_lineups_check_plan
before insert or update of slot on public.game_lineups
for each row
when (new.slot is not null)
execute function private.check_tactical_lineup();

-- Escolher o campo como padrão também é do Premium.
create or replace function private.check_lineup_style()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.lineup_style = 'field' then
    perform private.require_feature(new.owner_id, 'tactical_lineup');
  end if;
  return new;
end;
$$;

create trigger teams_check_lineup_style
before update of lineup_style on public.teams
for each row
when (new.lineup_style is distinct from old.lineup_style)
execute function private.check_lineup_style();
