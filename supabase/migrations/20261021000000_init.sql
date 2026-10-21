-- SportLeague - schema inicial
-- Perfis (admin/jogador), endereços, times, jogadores e convites.

-- =========================================================
-- Tipos
-- =========================================================
create type public.user_role as enum ('admin', 'player');
create type public.subscription_plan as enum ('free', 'premium');
create type public.sport_type as enum ('football', 'volleyball', 'basketball');
create type public.invite_status as enum ('pending', 'accepted', 'declined', 'canceled');

-- =========================================================
-- Funções utilitárias
-- =========================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =========================================================
-- Perfis
-- =========================================================
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 120),
  role public.user_role not null,
  plan public.subscription_plan not null default 'free',
  phone text,
  birth_date date,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

-- Cria o perfil automaticamente a partir dos metadados do cadastro
-- (full_name e role enviados em supabase.auth.signUp(data: {...})).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 'Usuário'),
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'player')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Impede que o usuário altere pelo app o próprio plano (alterado apenas
-- pelo backend de pagamentos) ou o tipo de perfil escolhido no cadastro.
create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and (new.plan is distinct from old.plan or new.role is distinct from old.role) then
    raise exception 'plan and role cannot be changed by the client';
  end if;
  return new;
end;
$$;

create trigger profiles_protect_fields
before update on public.profiles
for each row execute function public.protect_profile_fields();

alter table public.profiles enable row level security;

create policy "Perfis visíveis para usuários autenticados"
on public.profiles for select
to authenticated
using (true);

create policy "Usuário atualiza o próprio perfil"
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- =========================================================
-- Endereços (um por perfil)
-- =========================================================
create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles (id) on delete cascade,
  zip_code text not null,
  street text not null,
  number text not null,
  complement text,
  neighborhood text not null,
  city text not null,
  state char(2) not null,
  country text not null default 'BR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger addresses_set_updated_at
before update on public.addresses
for each row execute function public.set_updated_at();

alter table public.addresses enable row level security;

create policy "Usuário vê o próprio endereço"
on public.addresses for select
to authenticated
using ((select auth.uid()) = profile_id);

create policy "Usuário cria o próprio endereço"
on public.addresses for insert
to authenticated
with check ((select auth.uid()) = profile_id);

create policy "Usuário atualiza o próprio endereço"
on public.addresses for update
to authenticated
using ((select auth.uid()) = profile_id)
with check ((select auth.uid()) = profile_id);

create policy "Usuário remove o próprio endereço"
on public.addresses for delete
to authenticated
using ((select auth.uid()) = profile_id);

-- =========================================================
-- Times
-- =========================================================
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  sport public.sport_type not null default 'football',
  description text,
  logo_url text,
  city text,
  state char(2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index teams_owner_id_idx on public.teams (owner_id);
create index teams_name_idx on public.teams (lower(name));

create trigger teams_set_updated_at
before update on public.teams
for each row execute function public.set_updated_at();

create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p where p.id = uid and p.role = 'admin'
  );
$$;

create or replace function public.is_team_owner(team uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.teams t where t.id = team and t.owner_id = uid
  );
$$;

alter table public.teams enable row level security;

create policy "Times visíveis para usuários autenticados"
on public.teams for select
to authenticated
using (true);

create policy "Administradores criam times"
on public.teams for insert
to authenticated
with check (
  (select auth.uid()) = owner_id and public.is_admin((select auth.uid()))
);

create policy "Dono atualiza o time"
on public.teams for update
to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

create policy "Dono remove o time"
on public.teams for delete
to authenticated
using ((select auth.uid()) = owner_id);

-- =========================================================
-- Jogadores do time
-- Um jogador pode ser cadastrado pelo administrador apenas com nome
-- (profile_id nulo) ou estar vinculado a um usuário do app.
-- =========================================================
create table public.team_players (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete set null,
  name text not null check (char_length(name) between 2 and 120),
  position text,
  jersey_number smallint check (jersey_number between 0 and 999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (team_id, profile_id)
);

create index team_players_team_id_idx on public.team_players (team_id);
create index team_players_profile_id_idx on public.team_players (profile_id);

create trigger team_players_set_updated_at
before update on public.team_players
for each row execute function public.set_updated_at();

alter table public.team_players enable row level security;

create policy "Jogadores visíveis para usuários autenticados"
on public.team_players for select
to authenticated
using (true);

create policy "Dono do time cadastra jogadores"
on public.team_players for insert
to authenticated
with check (public.is_team_owner(team_id, (select auth.uid())));

create policy "Dono do time atualiza jogadores"
on public.team_players for update
to authenticated
using (public.is_team_owner(team_id, (select auth.uid())))
with check (public.is_team_owner(team_id, (select auth.uid())));

create policy "Dono remove jogador ou jogador sai do time"
on public.team_players for delete
to authenticated
using (
  public.is_team_owner(team_id, (select auth.uid()))
  or (select auth.uid()) = profile_id
);

-- =========================================================
-- Convites / solicitações de entrada no time
-- direction = 'invite'  -> enviado pelo administrador ao jogador
-- direction = 'request' -> solicitado pelo jogador ao time
-- =========================================================
create table public.team_invites (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  direction text not null check (direction in ('invite', 'request')),
  status public.invite_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

create unique index team_invites_one_pending_idx
on public.team_invites (team_id, profile_id)
where status = 'pending';

alter table public.team_invites enable row level security;

create policy "Envolvidos veem o convite"
on public.team_invites for select
to authenticated
using (
  (select auth.uid()) = profile_id
  or public.is_team_owner(team_id, (select auth.uid()))
);

create policy "Dono convida ou jogador solicita"
on public.team_invites for insert
to authenticated
with check (
  (select auth.uid()) = created_by
  and status = 'pending'
  and (
    (direction = 'invite' and public.is_team_owner(team_id, (select auth.uid())))
    or (direction = 'request' and (select auth.uid()) = profile_id)
  )
);

create policy "Envolvidos respondem o convite"
on public.team_invites for update
to authenticated
using (
  (select auth.uid()) = profile_id
  or public.is_team_owner(team_id, (select auth.uid()))
)
with check (
  (select auth.uid()) = profile_id
  or public.is_team_owner(team_id, (select auth.uid()))
);
