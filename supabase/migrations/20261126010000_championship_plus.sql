-- Campeonatos mais completos:
--
-- * Suspensão automática: expulsão (vermelho ou 2º amarelo) suspende
--   [red_games] jogos; a cada [yellow_limit] amarelos acumulados, 1 jogo
--   (0 desliga). Vale para o próximo jogo do time no campeonato; a
--   escalação e a súmula avisam (não bloqueiam).
-- * Inscrição por link: o organizador liga um código; times da plataforma
--   pedem para entrar (pelo dono do time) e times sem conta mandam nome,
--   responsável e elenco. O organizador aprova ou recusa; aprovado sem
--   conta vira um time fictício do organizador.
-- * Estatísticas: artilharia, assistências, cartões, ataque e defesa, fair
--   play (amarelo 1 ponto, vermelho 3) e seleção da rodada (os craques de
--   cada jogo e o craque da rodada), no app, no site e na página pública.

alter table public.championships
  add column yellow_limit smallint not null default 3 check (yellow_limit between 0 and 10),
  add column red_games smallint not null default 1 check (red_games between 0 and 5),
  add column signup_enabled boolean not null default false,
  add column signup_code text unique check (signup_code ~ '^[a-z0-9]{8}$');

-- ---------------------------------------------------------------------------
-- Pedidos de inscrição
-- ---------------------------------------------------------------------------

create table public.championship_requests (
  id uuid primary key default gen_random_uuid(),
  championship_id uuid not null references public.championships (id) on delete cascade,
  -- Time da plataforma (pedido pelo dono) ou nulo (time sem conta).
  team_id uuid references public.teams (id) on delete cascade,
  requested_by uuid references public.profiles (id) on delete set null,
  name text not null check (char_length(name) between 2 and 60),
  contact_name text check (char_length(contact_name) <= 80),
  -- Elenco do time sem conta: [{name, number}].
  players jsonb not null default '[]'::jsonb check (jsonb_typeof(players) = 'array'),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  entry_id uuid references public.championship_teams (id) on delete set null,
  created_at timestamptz not null default now(),
  answered_at timestamptz
);

create index championship_requests_championship_idx on public.championship_requests (championship_id, created_at);
create index championship_requests_team_idx on public.championship_requests (team_id);
create index championship_requests_requested_by_idx on public.championship_requests (requested_by);
create index championship_requests_entry_idx on public.championship_requests (entry_id);
create unique index championship_requests_one_pending_team
  on public.championship_requests (championship_id, team_id) where status = 'pending' and team_id is not null;

-- Só pelas funções.
alter table public.championship_requests enable row level security;

-- Inscrição aprovada entra aceita (sem o convite para o dono responder).
create or replace function private.prepare_championship_team()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.team_id is not null then
    select t.name,
           case when t.owner_id = c.owner_id
                  or coalesce(current_setting('sportleague.entry_accepted', true), '') = '1'
                then 'accepted' else 'invited' end
    into new.name, new.status
    from public.teams t, public.championships c
    where t.id = new.team_id and c.id = new.championship_id;
    new.logo_url := null;
  else
    select name, logo_url into new.name, new.logo_url
    from public.guest_teams where id = new.guest_team_id;
    new.status := 'accepted';
  end if;
  return new;
end;
$$;

-- Liga ou desliga a inscrição por link (o organizador). Devolve o código.
create or replace function public.set_championship_signup(
  p_championship uuid,
  p_enabled boolean,
  p_new_code boolean default false
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  select signup_code into v_code from public.championships
  where id = p_championship and owner_id = (select auth.uid());
  if not found then
    raise exception 'Só o organizador muda a inscrição por link.';
  end if;
  if v_code is null or p_new_code then
    loop
      v_code := lower(substr(regexp_replace(
        encode(extensions.gen_random_bytes(12), 'base64'), '[^a-zA-Z0-9]', '', 'g'), 1, 8));
      exit when length(v_code) = 8
        and not exists (select 1 from public.championships where signup_code = v_code);
    end loop;
  end if;
  update public.championships
     set signup_enabled = p_enabled, signup_code = v_code
   where id = p_championship;
  return v_code;
end;
$$;

-- Campeonato pelo código da inscrição (página de inscrição, sem login).
-- Com login, traz os times do administrador que ainda podem pedir.
create or replace function public.championship_signup_info(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'modality', c.modality,
    'format', c.format,
    'team_count', c.team_count,
    'entries', (select count(*) from public.championship_teams ct
                where ct.championship_id = c.id and ct.status <> 'declined'),
    'open', c.signup_enabled and c.status = 'draft',
    'organizer', private.person_name(c.owner_id),
    'public_slug', case when c.public_enabled then c.public_slug end,
    'my_teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'name', t.name,
        'logo_url', t.logo_url,
        'status', case
          when exists (select 1 from public.championship_teams ct
                       where ct.championship_id = c.id and ct.team_id = t.id) then 'entered'
          when exists (select 1 from public.championship_requests r
                       where r.championship_id = c.id and r.team_id = t.id and r.status = 'pending') then 'pending'
          else 'available' end
      ) order by t.name)
      from public.teams t
      where t.owner_id = (select auth.uid()) and t.inactive_at is null
    ), '[]'::jsonb)
  )
  from public.championships c
  where c.signup_code = p_code;
$$;

-- Vagas: ainda cabe mais um time?
create or replace function private.championship_has_room(p_championship uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select c.team_count is null
      or (select count(*) from public.championship_teams ct
          where ct.championship_id = c.id and ct.status <> 'declined') < c.team_count
  from public.championships c where c.id = p_championship;
$$;

-- Pedido de um time da plataforma (o dono do time, logado).
create or replace function public.request_championship_entry(p_code text, p_team uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
begin
  select * into c from public.championships where signup_code = p_code;
  if c.id is null or not c.signup_enabled or c.status <> 'draft' then
    raise exception 'As inscrições deste campeonato estão fechadas.';
  end if;
  if not private.is_team_owner(p_team, (select auth.uid())) then
    raise exception 'Só o dono do time pede a inscrição.';
  end if;
  if exists (select 1 from public.championship_teams where championship_id = c.id and team_id = p_team) then
    raise exception 'Este time já está no campeonato.';
  end if;
  if not private.championship_has_room(c.id) then
    raise exception 'O campeonato já está com todas as vagas.';
  end if;
  insert into public.championship_requests (championship_id, team_id, requested_by, name)
  select c.id, t.id, (select auth.uid()), t.name from public.teams t where t.id = p_team
  on conflict do nothing;
  perform private.notify_championship(
    c.owner_id, 'championship_request', c.name,
    private.team_name(p_team) || ' pediu para entrar no campeonato.', null, c.id
  );
end;
$$;

-- Pedido de um time sem conta (sem login): nome, responsável e elenco.
create or replace function public.request_championship_guest_entry(
  p_code text,
  p_name text,
  p_contact text,
  p_players jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
  v_players jsonb;
begin
  select * into c from public.championships where signup_code = p_code;
  if c.id is null or not c.signup_enabled or c.status <> 'draft' then
    raise exception 'As inscrições deste campeonato estão fechadas.';
  end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Informe o nome do time.';
  end if;
  if char_length(trim(coalesce(p_contact, ''))) < 2 then
    raise exception 'Informe o nome do responsável.';
  end if;
  if not private.championship_has_room(c.id) then
    raise exception 'O campeonato já está com todas as vagas.';
  end if;
  -- Contra abuso: no máximo 30 pedidos esperando por campeonato.
  if (select count(*) from public.championship_requests
      where championship_id = c.id and status = 'pending') >= 30 then
    raise exception 'Muitos pedidos esperando o organizador. Tente mais tarde.';
  end if;
  -- Elenco: até 40 nomes, com número opcional.
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', left(trim(p->>'name'), 60),
           'number', case when (p->>'number') ~ '^[0-9]{1,3}$' then (p->>'number')::int end)), '[]'::jsonb)
  into v_players
  from (
    select p from jsonb_array_elements(case when jsonb_typeof(p_players) = 'array' then p_players else '[]' end) p
    where char_length(trim(coalesce(p->>'name', ''))) >= 2
    limit 40
  ) x;
  insert into public.championship_requests (championship_id, requested_by, name, contact_name, players)
  values (c.id, (select auth.uid()), left(trim(p_name), 60), left(trim(p_contact), 80), v_players);
  perform private.notify_championship(
    c.owner_id, 'championship_request', c.name,
    left(trim(p_name), 60) || ' pediu para entrar no campeonato.', null, c.id
  );
end;
$$;

-- Pedidos do campeonato (o organizador).
create or replace function public.championship_requests_list(p_championship uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_championship_owner(p_championship, (select auth.uid())) then
    raise exception 'Só o organizador vê os pedidos.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'name', r.name,
      'team_id', r.team_id,
      'logo_url', t.logo_url,
      'contact_name', coalesce(r.contact_name, private.person_name(r.requested_by)),
      'players', r.players,
      'status', r.status,
      'created_at', r.created_at
    ) order by (r.status = 'pending') desc, r.created_at desc)
    from public.championship_requests r
    left join public.teams t on t.id = r.team_id
    where r.championship_id = p_championship
  ), '[]'::jsonb);
end;
$$;

-- Aprova ou recusa um pedido (o organizador). Aprovado: time da plataforma
-- entra aceito; sem conta vira time fictício do organizador.
create or replace function public.answer_championship_request(p_request uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.championship_requests;
  c public.championships;
  v_guest uuid;
  v_entry uuid;
begin
  select * into r from public.championship_requests where id = p_request;
  select * into c from public.championships where id = r.championship_id;
  if r.id is null or c.owner_id is distinct from (select auth.uid()) then
    raise exception 'Só o organizador responde os pedidos.';
  end if;
  if r.status <> 'pending' then
    raise exception 'Este pedido já foi respondido.';
  end if;
  if not p_accept then
    update public.championship_requests set status = 'declined', answered_at = now() where id = r.id;
    if r.requested_by is not null then
      perform private.notify_championship(
        r.requested_by, 'championship_answer', c.name,
        'O organizador recusou o pedido do ' || r.name || '.', r.team_id, c.id
      );
    end if;
    return;
  end if;
  if c.status <> 'draft' then
    raise exception 'O campeonato já começou.';
  end if;
  if not private.championship_has_room(c.id) then
    raise exception 'O campeonato já está com todas as vagas.';
  end if;

  if r.team_id is not null then
    perform set_config('sportleague.entry_accepted', '1', true);
    insert into public.championship_teams (championship_id, team_id)
    values (c.id, r.team_id)
    on conflict (championship_id, team_id) do nothing
    returning id into v_entry;
    perform set_config('sportleague.entry_accepted', '', true);
  else
    insert into public.guest_teams (owner_id, name, modality)
    values (c.owner_id, r.name, c.modality)
    returning id into v_guest;
    insert into public.championship_teams (championship_id, guest_team_id)
    values (c.id, v_guest)
    returning id into v_entry;
  end if;

  update public.championship_requests
     set status = 'accepted', answered_at = now(), entry_id = v_entry
   where id = r.id;
  if r.requested_by is not null then
    perform private.notify_championship(
      r.requested_by, 'championship_answer', c.name,
      'O ' || r.name || ' foi aceito no campeonato.', r.team_id, c.id
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Cartões e suspensões
-- ---------------------------------------------------------------------------

-- Situação de cartões de cada atleta (dos times da plataforma) no
-- campeonato, jogo a jogo na ordem dos jogos do time: amarelos e vermelhos,
-- amarelos acumulados desde a última suspensão e se está suspenso no
-- próximo jogo do time (o primeiro ainda sem placar).
create or replace function private.championship_cards(p_championship uuid)
returns table (
  athlete_id uuid,
  entry_id uuid,
  team_id uuid,
  name text,
  team_name text,
  yellow_cards integer,
  red_cards integer,
  yellow_pending integer,
  suspended boolean,
  reason text,
  next_match_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.championships;
  e record;
  a record;
  m record;
  s record;
  pending integer;
  acc integer;
  ytot integer;
  rtot integer;
  why text;
  v_next uuid;
begin
  select * into c from public.championships where id = p_championship;
  for e in
    select ct.id, ct.team_id, ct.name from public.championship_teams ct
    where ct.championship_id = p_championship and ct.team_id is not null and ct.status = 'accepted'
  loop
    -- Próximo jogo do time: o primeiro (na ordem) ainda sem placar.
    select m2.id into v_next
    from public.championship_matches m2
    where m2.championship_id = p_championship
      and (m2.home_id = e.id or m2.away_id = e.id)
      and m2.home_score is null
    order by m2.scheduled_at nulls last, m2.stage, m2.round, m2.slot
    limit 1;

    for a in
      select tp.id, coalesce(nullif(pr.nickname, ''), tp.name) as display
      from public.team_players tp
      left join public.profiles pr on pr.id = tp.profile_id
      where tp.team_id = e.team_id
    loop
      pending := 0; acc := 0; ytot := 0; rtot := 0; why := null;
      for m in
        select m3.id, m3.round, g.id as game_id
        from public.championship_matches m3
        left join public.games g on g.championship_match_id = m3.id
        where m3.championship_id = p_championship
          and (m3.home_id = e.id or m3.away_id = e.id)
          and m3.home_score is not null
        order by m3.scheduled_at nulls last, m3.stage, m3.round, m3.slot
      loop
        -- Suspensão cumprida neste jogo.
        if pending > 0 then
          pending := pending - 1;
        end if;
        select gps.yellow_cards, gps.red_card into s
        from public.game_player_stats gps
        where gps.game_id = m.game_id and gps.athlete_id = a.id;
        if s is null then
          continue;
        end if;
        if s.red_card then
          rtot := rtot + 1;
          if c.red_games > 0 then
            pending := pending + c.red_games;
            why := 'Expulso';
          end if;
          -- O amarelo que virou vermelho não acumula; um amarelo antes de
          -- um vermelho direto, sim.
          if s.yellow_cards = 1 then
            ytot := ytot + 1;
          end if;
        elsif s.yellow_cards > 0 then
          ytot := ytot + s.yellow_cards;
          acc := acc + s.yellow_cards;
          if c.yellow_limit > 0 and acc >= c.yellow_limit then
            pending := pending + 1;
            acc := acc - c.yellow_limit;
            why := c.yellow_limit || ' amarelos';
          end if;
        end if;
      end loop;
      if ytot > 0 or rtot > 0 then
        athlete_id := a.id;
        entry_id := e.id;
        team_id := e.team_id;
        name := a.display;
        team_name := e.name;
        yellow_cards := ytot;
        red_cards := rtot;
        yellow_pending := acc;
        suspended := pending > 0 and v_next is not null;
        reason := case when pending > 0 then why end;
        next_match_id := v_next;
        return next;
      end if;
    end loop;
  end loop;
end;
$$;

-- Atletas suspensos num jogo (escalação e súmula avisam): o jogo precisa
-- ser o próximo do time no campeonato.
create or replace function public.game_suspensions(p_game uuid)
returns table (athlete_id uuid, team_id uuid, reason text)
language sql
stable
security definer
set search_path = ''
as $$
  select x.athlete_id, x.team_id, x.reason
  from public.games g
  join public.championship_matches m on m.id = g.championship_match_id
  cross join lateral private.championship_cards(m.championship_id) x
  where g.id = p_game
    and x.suspended
    and x.next_match_id = m.id
    and (private.is_team_member(g.team_id, (select auth.uid()))
         or (g.opponent_team_id is not null
             and private.is_team_member(g.opponent_team_id, (select auth.uid()))));
$$;

-- ---------------------------------------------------------------------------
-- Estatísticas
-- ---------------------------------------------------------------------------

-- Números do campeonato (sem conferir quem vê: as funções públicas abaixo
-- conferem).
create or replace function private.championship_stats_data(p_championship uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with games as (
    select g.id as game_id, m.id as match_id, m.stage, m.round, m.slot,
           m.home_id, m.away_id, m.home_score, m.away_score
    from public.championship_matches m
    join public.games g on g.championship_match_id = m.id
    where m.championship_id = p_championship
  ),
  stats as (
    select s.*, gm.match_id, gm.stage, gm.round,
           coalesce(nullif(pr.nickname, ''), tp.name) as display,
           t.name as team_name, t.logo_url
    from games gm
    join public.game_player_stats s on s.game_id = gm.game_id
    join public.team_players tp on tp.id = s.athlete_id
    left join public.profiles pr on pr.id = tp.profile_id
    join public.teams t on t.id = s.team_id
  ),
  players as (
    select athlete_id, display as name, team_name, logo_url,
           sum(goals)::int as goals, sum(assists)::int as assists,
           sum(case when red_card and yellow_cards = 2 then 0 else yellow_cards end)::int as yellow_cards,
           (count(*) filter (where red_card))::int as red_cards,
           (count(*) filter (where best_player))::int as best_player,
           count(*)::int as games
    from stats
    group by athlete_id, display, team_name, logo_url
  ),
  played as (
    select * from public.championship_matches
    where championship_id = p_championship and home_score is not null
  ),
  team_rows as (
    select ct.id, ct.name, coalesce(t.logo_url, ct.logo_url) as logo_url,
           (select count(*) from played p where p.home_id = ct.id or p.away_id = ct.id)::int as played,
           coalesce((select sum(case when p.home_id = ct.id then p.home_score else p.away_score end)
                     from played p where p.home_id = ct.id or p.away_id = ct.id), 0)::int as goals_for,
           coalesce((select sum(case when p.home_id = ct.id then p.away_score else p.home_score end)
                     from played p where p.home_id = ct.id or p.away_id = ct.id), 0)::int as goals_against,
           coalesce((select sum(case when s.red_card and s.yellow_cards = 2 then 0 else s.yellow_cards end)
                     from stats s where s.team_id = ct.team_id), 0)::int as yellow_cards,
           coalesce((select count(*) from stats s where s.team_id = ct.team_id and s.red_card), 0)::int as red_cards
    from public.championship_teams ct
    left join public.teams t on t.id = ct.team_id
    where ct.championship_id = p_championship and ct.status = 'accepted'
  ),
  best as (
    select stage, round, match_id, display as name, team_name, logo_url, goals, assists,
           row_number() over (partition by stage, round order by goals desc, assists desc, display) as rank
    from stats where best_player
  ),
  rounds as (
    select stage, round,
           jsonb_agg(jsonb_build_object('name', name, 'team_name', team_name, 'logo_url', logo_url,
                                        'goals', goals, 'assists', assists, 'top', rank = 1)
                     order by rank) as players
    from best
    group by stage, round
  )
  select jsonb_build_object(
    'players', coalesce((select jsonb_agg(to_jsonb(p) - 'athlete_id' order by p.goals desc, p.assists desc, p.name) from players p), '[]'::jsonb),
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'name', r.name, 'logo_url', r.logo_url, 'played', r.played,
        'goals_for', r.goals_for, 'goals_against', r.goals_against,
        'yellow_cards', r.yellow_cards, 'red_cards', r.red_cards,
        'fair_play', r.yellow_cards + 3 * r.red_cards) order by r.name) from team_rows r), '[]'::jsonb),
    'suspended', coalesce((select jsonb_agg(jsonb_build_object(
        'name', x.name, 'team_name', x.team_name, 'reason', x.reason) order by x.team_name, x.name)
      from private.championship_cards(p_championship) x where x.suspended), '[]'::jsonb),
    'rounds', coalesce((select jsonb_agg(jsonb_build_object('stage', stage, 'round', round, 'players', players)
      order by stage desc, round desc) from rounds), '[]'::jsonb),
    'yellow_limit', (select yellow_limit from public.championships where id = p_championship),
    'red_games', (select red_games from public.championships where id = p_championship)
  );
$$;

-- Estatísticas para quem vê o campeonato (organizador e times inscritos).
create or replace function public.championship_stats(p_championship uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.can_see_championship(p_championship, (select auth.uid())) then
    raise exception 'Você não vê este campeonato.';
  end if;
  return private.championship_stats_data(p_championship);
end;
$$;

-- Campeonato público: o mesmo de antes, com as estatísticas e o elenco dos
-- times que se inscreveram sem conta.
create or replace function public.public_championship(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with c as (
    select * from public.championships where public_slug = p_slug and public_enabled
  ),
  entries as (
    select ct.id, ct.name, ct.status, ct.group_label, coalesce(t.logo_url, ct.logo_url) as logo_url,
           ct.guest_team_id is not null as guest, ct.created_at
    from public.championship_teams ct
    join c on c.id = ct.championship_id
    left join public.teams t on t.id = ct.team_id
    where ct.status <> 'declined'
  ),
  matches as (
    select m.id, m.stage, m.round, m.slot, m.group_label, m.home_id, m.away_id, m.scheduled_at,
           m.home_score, m.away_score, m.home_penalties, m.away_penalties,
           v.name as venue_name, v.city as venue_city, v.state as venue_state,
           private.public_match_live(m.id) as live
    from public.championship_matches m
    join c on c.id = m.championship_id
    left join public.venues v on v.id = m.venue_id
  ),
  players as (
    select coalesce(nullif(pr.nickname, ''), a.name) as name, t.name as team_name, t.logo_url,
           sum(s.goals)::integer as goals, sum(s.assists)::integer as assists, count(*)::integer as games,
           (count(*) filter (where s.best_player))::integer as best_player
    from c
    join public.championship_matches m on m.championship_id = c.id
    join public.games g on g.championship_match_id = m.id
    join public.game_player_stats s on s.game_id = g.id
    join public.team_players a on a.id = s.athlete_id
    left join public.profiles pr on pr.id = a.profile_id
    join public.teams t on t.id = s.team_id
    group by a.id, pr.nickname, a.name, t.name, t.logo_url
  )
  select case when not exists (select 1 from c) then null else jsonb_build_object(
    'championship', (select jsonb_build_object(
        'id', id, 'name', name, 'modality', modality, 'format', format, 'double_round', double_round,
        'group_count', group_count, 'qualifiers_per_group', qualifiers_per_group, 'team_count', team_count,
        'group_size', group_size, 'knockout_fill', knockout_fill, 'knockout_qualifiers', knockout_qualifiers,
        'status', status, 'created_at', created_at,
        'signup_code', case when signup_enabled and status = 'draft' then signup_code end) from c),
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'name', e.name, 'status', e.status, 'group_label', e.group_label,
        'logo_url', e.logo_url, 'guest', e.guest,
        'players', (select r.players from public.championship_requests r
                    where r.entry_id = e.id and r.status = 'accepted' limit 1)
      ) order by e.created_at) from entries e), '[]'::jsonb),
    'matches', coalesce((select jsonb_agg(to_jsonb(m) order by m.stage, m.round, m.slot) from matches m), '[]'::jsonb),
    'players', coalesce((select jsonb_agg(to_jsonb(p) order by p.goals desc, p.name) from players p), '[]'::jsonb),
    'stats', private.championship_stats_data((select id from c))
  ) end;
$$;

revoke execute on function
  private.championship_has_room(uuid),
  private.championship_cards(uuid),
  private.championship_stats_data(uuid)
from public, anon, authenticated;

revoke execute on function
  public.set_championship_signup(uuid, boolean, boolean),
  public.request_championship_entry(text, uuid),
  public.championship_requests_list(uuid),
  public.answer_championship_request(uuid, boolean),
  public.game_suspensions(uuid),
  public.championship_stats(uuid)
from public, anon;
grant execute on function
  public.set_championship_signup(uuid, boolean, boolean),
  public.request_championship_entry(text, uuid),
  public.championship_requests_list(uuid),
  public.answer_championship_request(uuid, boolean),
  public.game_suspensions(uuid),
  public.championship_stats(uuid)
to authenticated;

-- Sem login: ver o campeonato pelo código e pedir a inscrição sem conta.
revoke execute on function
  public.championship_signup_info(text),
  public.request_championship_guest_entry(text, text, text, jsonb)
from public;
grant execute on function
  public.championship_signup_info(text),
  public.request_championship_guest_entry(text, text, text, jsonb)
to anon, authenticated;
