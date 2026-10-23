-- Perfil do time: nova modalidade, mando, contatos e mídia (capa e uniformes).
--
-- "Futebol de Areia" passa a se chamar "Areia" só no app (o valor no banco
-- continua 'beach'). Fundação e cidade passam a ser exigidas pelo app; no
-- banco ficam opcionais para não quebrar times criados antes.

alter type public.team_modality add value if not exists 'challenge';

-- Como o time aceita jogar: só mandante (tem quadra/campo), só visitante
-- (não tem onde receber) ou ambos.
create type public.plays_as as enum ('home', 'away', 'both');

alter table public.teams
  add column plays_as public.plays_as not null default 'both',
  add column phone text check (phone ~ '^\d{10,11}$'),
  add column instagram text check (char_length(instagram) <= 100),
  add column facebook text check (char_length(facebook) <= 200),
  add column youtube text check (char_length(youtube) <= 200),
  add column website text check (char_length(website) <= 200),
  -- Imagens no bucket público team-logos, na pasta do dono.
  add column cover_url text,
  add column kit_urls text[] not null default '{}'
    check (cardinality(kit_urls) <= 3);

-- Se o time [p_team] aceita jogar como mandante ([p_home]) ou visitante.
create or replace function private.team_accepts_side(p_team uuid, p_home boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select t.plays_as = 'both'
      or (p_home and t.plays_as = 'home')
      or (not p_home and t.plays_as = 'away')
    from public.teams t
    where t.id = p_team
  ), true);
$$;

revoke execute on function private.team_accepts_side(uuid, boolean) from public, anon;
grant execute on function private.team_accepts_side(uuid, boolean) to authenticated;

-- Regra ao marcar: quem marca precisa aceitar o lado escolhido e o adversário
-- da plataforma, o lado oposto. Conferido ao marcar e quando quem marcou
-- muda o mando ou o adversário; jogos antigos continuam editáveis sem mudar
-- esses campos, e a exclusão de times não é barrada.
create or replace function public.check_game_sides()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.host_is_home is not distinct from old.host_is_home
     and (new.opponent_team_id is null
          or new.opponent_team_id is not distinct from old.opponent_team_id) then
    return new;
  end if;

  if not private.team_accepts_side(new.team_id, new.host_is_home) then
    raise exception 'team does not play on this side';
  end if;
  if new.opponent_team_id is not null
     and not private.team_accepts_side(new.opponent_team_id, not new.host_is_home) then
    raise exception 'opponent does not play on this side';
  end if;
  return new;
end;
$$;

create trigger games_check_sides
before insert or update on public.games
for each row execute function public.check_game_sides();
