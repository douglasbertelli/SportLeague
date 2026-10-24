-- Convites e pedidos para entrar num time.
--
-- 1. Cada time tem um código de convite (para mandar no WhatsApp). Ele fica
--    numa tabela à parte, que só o dono vê: os times são públicos e, no
--    próprio time, qualquer um leria o código. O dono pode gerar outro.
-- 2. O jogador entra com o código (join_team_with_code): vira atleta na hora.
-- 3. O jogador também pode pedir para entrar (team_invites, direction
--    'request'); o dono aceita ou recusa, e o jogador pode cancelar.
-- 4. Aceito (por código, pedido ou convite), o jogador vira atleta do time,
--    ligado à conta dele.

-- Código legível: sem 0/O, 1/I/L.
create or replace function private.new_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text := '';
begin
  for i in 1..8 loop
    code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return code;
end;
$$;

create table public.team_invite_codes (
  team_id uuid primary key references public.teams (id) on delete cascade,
  code text not null unique default private.new_invite_code()
    check (code ~ '^[A-Z0-9]{8}$'),
  updated_at timestamptz not null default now()
);

alter table public.team_invite_codes enable row level security;

create policy "Dono do time vê o código de convite"
on public.team_invite_codes for select
to authenticated
using (private.is_team_owner(team_invite_codes.team_id, (select auth.uid())));

-- Times existentes e novos ganham um código.
insert into public.team_invite_codes (team_id)
select id from public.teams;

create or replace function private.create_invite_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.team_invite_codes (team_id) values (new.id)
  on conflict (team_id) do nothing;
  return new;
end;
$$;

create trigger teams_create_invite_code
after insert on public.teams
for each row execute function private.create_invite_code();

-- O dono gera um código novo (o antigo deixa de valer).
create or replace function public.regenerate_invite_code(p_team uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  new_code text;
begin
  if not private.is_team_owner(p_team, (select auth.uid())) then
    raise exception 'only the team owner can change the invite code';
  end if;
  loop
    new_code := private.new_invite_code();
    exit when not exists (
      select 1 from public.team_invite_codes c where c.code = new_code
    );
  end loop;
  update public.team_invite_codes
  set code = new_code, updated_at = now()
  where team_id = p_team;
  return new_code;
end;
$$;

-- Time do código, para mostrar antes de entrar (nulo se não existir).
create or replace function public.team_by_invite_code(p_code text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.team_id
  from public.team_invite_codes c
  where c.code = upper(trim(p_code));
$$;

-- Pedidos: só jogadores pedem para entrar; convites, só o dono do time.
drop policy "Dono convida ou jogador solicita" on public.team_invites;

create policy "Dono convida ou jogador pede para entrar"
on public.team_invites for insert
to authenticated
with check (
  (select auth.uid()) = created_by
  and status = 'pending'
  and (
    (direction = 'invite'
      and private.is_team_owner(team_invites.team_id, (select auth.uid())))
    or (direction = 'request'
      and (select auth.uid()) = profile_id
      and exists (
        select 1 from public.profiles p
        where p.id = (select auth.uid()) and p.role = 'player'
      ))
  )
);

-- Quem pode responder: o pedido, o dono aceita/recusa e o jogador cancela;
-- o convite, o jogador aceita/recusa e o dono cancela. Só a situação muda,
-- e só de pendente.
create or replace function public.check_invite_change()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  is_owner boolean;
begin
  -- O backend e a entrada por código (join_team_with_code) passam.
  if uid is null or current_setting('app.invite_join', true) = 'on' then
    new.responded_at := coalesce(new.responded_at, now());
    return new;
  end if;
  if (to_jsonb(new) - array['status', 'responded_at'])
     is distinct from (to_jsonb(old) - array['status', 'responded_at']) then
    raise exception 'only the invite status can change';
  end if;
  if old.status <> 'pending' then
    raise exception 'invite already answered';
  end if;

  is_owner := private.is_team_owner(old.team_id, uid);
  if old.direction = 'request' then
    if not (
      (is_owner and new.status in ('accepted', 'declined'))
      or (uid = old.profile_id and new.status = 'canceled')
    ) then
      raise exception 'invalid answer to the request';
    end if;
  else
    if not (
      (uid = old.profile_id and new.status in ('accepted', 'declined'))
      or (is_owner and new.status = 'canceled')
    ) then
      raise exception 'invalid answer to the invite';
    end if;
  end if;
  new.responded_at := now();
  return new;
end;
$$;

create trigger team_invites_check_change
before update on public.team_invites
for each row execute function public.check_invite_change();

-- Aceito: o jogador vira atleta do time (se ainda não for).
create or replace function private.add_player_on_accept()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'accepted'
     and (tg_op = 'INSERT' or old.status is distinct from 'accepted') then
    insert into public.team_players (team_id, profile_id, name)
    select new.team_id, p.id, p.full_name
    from public.profiles p
    where p.id = new.profile_id
    on conflict (team_id, profile_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger team_invites_add_player
after insert or update on public.team_invites
for each row execute function private.add_player_on_accept();

-- Entrar com o código: o jogador logado vira atleta do time do código. Um
-- pedido pendente para o mesmo time vira aceito; senão fica registrado um
-- pedido já aceito.
create or replace function public.join_team_with_code(p_code text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  team uuid;
begin
  if uid is null or not exists (
    select 1 from public.profiles p where p.id = uid and p.role = 'player'
  ) then
    raise exception 'only players can join a team';
  end if;
  team := public.team_by_invite_code(p_code);
  if team is null then
    raise exception 'invalid invite code';
  end if;
  if exists (
    select 1 from public.team_players tp
    where tp.team_id = team and tp.profile_id = uid
  ) then
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

revoke execute on function private.new_invite_code() from public, anon;
revoke execute on function public.regenerate_invite_code(uuid) from public, anon;
revoke execute on function public.team_by_invite_code(text) from public, anon;
revoke execute on function public.join_team_with_code(text) from public, anon;
grant execute on function public.regenerate_invite_code(uuid) to authenticated;
grant execute on function public.team_by_invite_code(text) to authenticated;
grant execute on function public.join_team_with_code(text) to authenticated;
