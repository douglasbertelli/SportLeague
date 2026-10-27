-- Técnico: entra nos times com o código de convite ou pedindo pelo perfil do
-- time (o dono aceita), como o jogador. Vê tudo do time (jogos, atletas,
-- fotos, estatísticas) e monta a escalação e a súmula; não edita o time, não
-- marca jogos nem cadastra atletas.

create table public.team_coaches (
  team_id uuid not null references public.teams (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (team_id, profile_id)
);

create index team_coaches_profile_id on public.team_coaches (profile_id);

alter table public.team_coaches enable row level security;

create or replace function private.is_team_coach(team uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.team_coaches c
    where c.team_id = team and c.profile_id = uid
  );
$$;

-- Dono ou técnico: quem monta escalação e súmula.
create or replace function private.is_team_staff(team uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_team_owner(team, uid) or private.is_team_coach(team, uid);
$$;

revoke execute on function private.is_team_coach(uuid, uuid) from public, anon;
grant execute on function private.is_team_coach(uuid, uuid) to authenticated;
revoke execute on function private.is_team_staff(uuid, uuid) from public, anon;
grant execute on function private.is_team_staff(uuid, uuid) to authenticated;

-- O técnico e o dono veem; entra só pelo convite aceito (gatilho abaixo).
create policy "Técnico e dono veem o vínculo"
on public.team_coaches for select
to authenticated
using (
  profile_id = (select auth.uid())
  or private.is_team_owner(team_id, (select auth.uid()))
);

-- O técnico sai do time ou o dono o remove.
create policy "Técnico sai ou dono remove"
on public.team_coaches for delete
to authenticated
using (
  profile_id = (select auth.uid())
  or private.is_team_owner(team_id, (select auth.uid()))
);

-- Convites e pedidos dizem se são de jogador ou de técnico.
alter table public.team_invites
  add column kind text not null default 'player'
    check (kind in ('player', 'coach'));

-- Pedido feito pelo próprio usuário: o tipo segue o perfil dele.
create or replace function private.set_invite_kind()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.direction = 'request' then
    new.kind := case
      when exists (
        select 1 from public.profiles p
        where p.id = new.profile_id and p.role = 'coach'
      ) then 'coach'
      else 'player'
    end;
  end if;
  return new;
end;
$$;

create trigger team_invites_set_kind
before insert on public.team_invites
for each row execute function private.set_invite_kind();

-- Jogador ou técnico pede para entrar.
drop policy "Dono convida ou jogador pede para entrar" on public.team_invites;
create policy "Dono convida ou jogador e técnico pedem para entrar"
on public.team_invites for insert
to authenticated
with check (
  (select auth.uid()) = created_by
  and status = 'pending'
  and (
    (direction = 'invite' and private.is_team_owner(team_id, (select auth.uid())))
    or (
      direction = 'request'
      and (select auth.uid()) = profile_id
      and exists (
        select 1 from public.profiles p
        where p.id = (select auth.uid()) and p.role in ('player', 'coach')
      )
    )
  )
);

-- Aceito: o técnico entra na comissão; o jogador, no elenco.
create or replace function private.add_player_on_accept()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'accepted'
     and (tg_op = 'INSERT' or old.status is distinct from 'accepted') then
    if new.kind = 'coach' then
      insert into public.team_coaches (team_id, profile_id)
      values (new.team_id, new.profile_id)
      on conflict do nothing;
    else
      insert into public.team_players (team_id, profile_id, name)
      select new.team_id, p.id, p.full_name
      from public.profiles p
      where p.id = new.profile_id
      on conflict (team_id, profile_id) do nothing;
    end if;
  end if;
  return new;
end;
$$;

-- Entrar com o código: jogador ou técnico.
create or replace function public.join_team_with_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  user_role public.user_role;
  team uuid;
begin
  select p.role into user_role from public.profiles p where p.id = uid;
  if uid is null or user_role is null or user_role not in ('player', 'coach') then
    raise exception 'only players and coaches can join a team';
  end if;
  team := public.team_by_invite_code(p_code);
  if team is null then
    raise exception 'invalid invite code';
  end if;
  if exists (
    select 1 from public.team_players tp
    where tp.team_id = team and tp.profile_id = uid
  ) or private.is_team_coach(team, uid) then
    raise exception 'already in the team';
  end if;

  perform set_config('app.invite_join', 'on', true);
  update public.team_invites
  set status = 'accepted'
  where team_id = team and profile_id = uid and status = 'pending';
  if not found then
    insert into public.team_invites
      (team_id, profile_id, created_by, direction, status, responded_at)
    values (team, uid, uid, 'request', 'accepted', now());
  end if;
  perform set_config('app.invite_join', 'off', true);
  return team;
end;
$$;

-- O técnico vê os jogos dos times dele.
drop policy "Os dois times veem o amistoso" on public.games;
create policy "Os dois times veem o amistoso"
on public.games for select
to authenticated
using (
  private.is_team_staff(team_id, (select auth.uid()))
  or (
    opponent_team_id is not null
    and private.is_team_staff(opponent_team_id, (select auth.uid()))
  )
  or exists (
    select 1 from public.team_players p
    where p.profile_id = (select auth.uid())
      and (p.team_id = games.team_id or p.team_id = games.opponent_team_id)
  )
);

-- ... e as fotos dos atletas.
drop policy "Dono e atletas do time veem as fotos" on storage.objects;
create policy "Dono, técnicos e atletas do time veem as fotos"
on storage.objects for select
to authenticated
using (
  bucket_id = 'athlete-photos'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.team_players p
      where p.team_id::text = (storage.foldername(objects.name))[2]
        and p.profile_id = (select auth.uid())
    )
    or exists (
      select 1 from public.team_coaches c
      where c.team_id::text = (storage.foldername(objects.name))[2]
        and c.profile_id = (select auth.uid())
    )
  )
);

-- O técnico também lança a súmula.
create or replace function private.can_edit_player_stats(
  p_game uuid,
  p_team uuid,
  p_athlete uuid
)
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
        and g.status = 'scheduled'
        and g.scheduled_at <= now() + interval '1 hour'
    )
    and exists (
      select 1 from public.team_players a
      where a.id = p_athlete and a.team_id = p_team
    );
$$;

drop policy "Time corrige os dados dos seus atletas" on public.game_player_stats;
create policy "Time corrige os dados dos seus atletas"
on public.game_player_stats for update
to authenticated
using (private.is_team_staff(team_id, (select auth.uid())))
with check (private.can_edit_player_stats(game_id, team_id, athlete_id));

drop policy "Time tira atleta da súmula" on public.game_player_stats;
create policy "Time tira atleta da súmula"
on public.game_player_stats for delete
to authenticated
using (private.is_team_staff(team_id, (select auth.uid())));

-- Escalação do jogo: titulares e reservas de cada time, montada pelo dono ou
-- pelo técnico antes e durante a partida. Quem vê o jogo vê a escalação.
create table public.game_lineups (
  game_id uuid not null references public.games (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  athlete_id uuid not null references public.team_players (id) on delete cascade,
  starter boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (game_id, athlete_id)
);

create index game_lineups_team_id on public.game_lineups (team_id);
create index game_lineups_athlete_id on public.game_lineups (athlete_id);

alter table public.game_lineups enable row level security;

create or replace function private.can_edit_lineup(
  p_game uuid,
  p_team uuid,
  p_athlete uuid
)
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
    )
    and exists (
      select 1 from public.team_players a
      where a.id = p_athlete and a.team_id = p_team
    );
$$;

revoke execute on function private.can_edit_lineup(uuid, uuid, uuid) from public, anon;
grant execute on function private.can_edit_lineup(uuid, uuid, uuid) to authenticated;

create policy "Quem vê o jogo vê a escalação"
on public.game_lineups for select
to authenticated
using (exists (select 1 from public.games g where g.id = game_lineups.game_id));

create policy "Dono ou técnico escala"
on public.game_lineups for insert
to authenticated
with check (private.can_edit_lineup(game_id, team_id, athlete_id));

create policy "Dono ou técnico muda a escalação"
on public.game_lineups for update
to authenticated
using (private.is_team_staff(team_id, (select auth.uid())))
with check (private.can_edit_lineup(game_id, team_id, athlete_id));

create policy "Dono ou técnico tira da escalação"
on public.game_lineups for delete
to authenticated
using (private.is_team_staff(team_id, (select auth.uid())));
