-- Súmula ao vivo: os lances do jogo com o minuto (gol, gol contra, pênalti
-- perdido ou defendido, cartões e substituições).
--
-- * Placar automático: gol e gol contra somam no placar do jogo na hora (e
--   saem dele ao apagar o lance). Quem marcou ainda corrige o placar à mão.
--   No campeonato, o placar segue para a classificação pela sincronização
--   que já existe.
-- * Súmula dos atletas: gol, assistência e cartões entram em
--   game_player_stats; quem entra numa substituição passa a ter jogado.
-- * Quem lança: o placar é de quem marcou o jogo (como hoje). Ele lança os
--   gols dos dois lados (do adversário, sem o autor quando o adversário é da
--   plataforma); o adversário da plataforma completa autor e assistência
--   dos gols dele e lança os próprios cartões, pênaltis e substituições.
--   Contra time convidado, quem marcou lança tudo.
-- * Avisos: gol, início, intervalo e fim de jogo para os atletas, técnicos e
--   donos dos dois times e para os donos dos times que os seguem.
-- * Link público: todo jogo pode ganhar um código (/j/código no site) para
--   quem não tem conta acompanhar ao vivo; o campeonato público mostra os
--   lances dos jogos dele.

create type public.game_event_kind as enum (
  'goal', 'own_goal', 'penalty_missed', 'penalty_saved',
  'yellow_card', 'second_yellow', 'red_card', 'substitution'
);

create table public.game_events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  -- Lado de quem fez o lance: 'host' (quem marcou o jogo) ou 'opponent'.
  -- No gol contra, o gol vale para o outro lado.
  side text not null check (side in ('host', 'opponent')),
  kind public.game_event_kind not null,
  athlete_id uuid references public.team_players (id) on delete set null,
  -- Assistência (gol) ou quem entrou (substituição).
  related_athlete_id uuid references public.team_players (id) on delete set null,
  -- Gol de pênalti.
  penalty boolean not null default false,
  -- Tempo e segundos corridos dele, tirados do relógio da partida (vazios
  -- sem relógio).
  phase public.match_phase check (phase is null or phase in ('first', 'second')),
  clock_seconds integer check (clock_seconds between 0 and 36000),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  check (kind = 'goal' or not penalty),
  check (related_athlete_id is null or kind in ('goal', 'substitution')),
  check (related_athlete_id is null or related_athlete_id is distinct from athlete_id)
);

create index game_events_game_id_idx on public.game_events (game_id, created_at);
create index game_events_athlete_id_idx on public.game_events (athlete_id);
create index game_events_related_athlete_id_idx on public.game_events (related_athlete_id);
create index game_events_created_by_idx on public.game_events (created_by);

alter table public.game_events enable row level security;

-- Time de cada lado do jogo (nulo: adversário convidado).
create or replace function private.game_side_team(p_game uuid, p_side text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_side = 'host' then g.team_id else g.opponent_team_id end
  from public.games g where g.id = p_game;
$$;

-- Quem pode lançar (ou apagar) um lance deste tipo deste lado: jogo marcado
-- que começa em até uma hora (ou já começou).
create or replace function private.can_add_game_event(
  p_game uuid,
  p_side text,
  p_kind public.game_event_kind
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.games g
    where g.id = p_game
      and g.status = 'scheduled'
      and g.scheduled_at <= now() + interval '1 hour'
      and (
        -- Quem marcou: o lado dele, os gols dos dois lados e tudo do
        -- adversário convidado.
        (private.is_team_owner(g.team_id, (select auth.uid()))
          and (p_side = 'host'
               or p_kind in ('goal', 'own_goal')
               or g.opponent_team_id is null))
        -- Adversário da plataforma: os lances dele, menos gols (o placar é
        -- de quem marcou).
        or (p_side = 'opponent'
            and g.opponent_team_id is not null
            and p_kind not in ('goal', 'own_goal')
            and private.is_team_owner(g.opponent_team_id, (select auth.uid())))
      )
  );
$$;

-- Quem completa autor e assistência de um lance: o dono do time daquele
-- lado (ou quem marcou, contra convidado).
create or replace function private.can_edit_game_event(p_game uuid, p_side text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.games g
    where g.id = p_game
      and g.status = 'scheduled'
      and private.is_team_owner(
        coalesce(
          case when p_side = 'host' then g.team_id else g.opponent_team_id end,
          g.team_id
        ),
        (select auth.uid())
      )
  );
$$;

create policy "Quem vê o jogo vê os lances"
on public.game_events for select
to authenticated
using (exists (select 1 from public.games g where g.id = game_events.game_id));

create policy "Time lança os lances"
on public.game_events for insert
to authenticated
with check (private.can_add_game_event(game_id, side, kind));

create policy "Time completa os lances"
on public.game_events for update
to authenticated
using (private.can_edit_game_event(game_id, side))
with check (private.can_edit_game_event(game_id, side));

create policy "Time apaga os lances"
on public.game_events for delete
to authenticated
using (private.can_add_game_event(game_id, side, kind));

-- Antes de gravar: atletas do time certo, minuto pelo relógio e, ao
-- completar, só autor, assistência e pênalti mudam.
create or replace function private.check_game_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  g public.games;
  side_team uuid;
begin
  select * into g from public.games where id = new.game_id;
  side_team := case when new.side = 'host' then g.team_id else g.opponent_team_id end;

  if tg_op = 'UPDATE' then
    if (to_jsonb(new) - array['athlete_id', 'related_athlete_id', 'penalty'])
       is distinct from
       (to_jsonb(old) - array['athlete_id', 'related_athlete_id', 'penalty']) then
      raise exception 'only the players of an event can change';
    end if;
  else
    new.created_by := (select auth.uid());
    -- Minuto pelo relógio, se o app não mandou.
    if new.phase is null and g.match_phase is not null then
      new.phase := case when g.match_phase in ('interval', 'first') then 'first'
                        else 'second' end;
      new.clock_seconds := case
        when g.match_phase = 'interval' then coalesce(g.period_minutes, 0) * 60
        else g.clock_elapsed + coalesce(
          floor(extract(epoch from now() - g.clock_started_at))::integer, 0)
      end;
    end if;
  end if;

  if new.athlete_id is not null and not exists (
    select 1 from public.team_players a
    where a.id = new.athlete_id and a.team_id = side_team
  ) then
    raise exception 'the player is not from this team';
  end if;
  if new.related_athlete_id is not null and not exists (
    select 1 from public.team_players a
    where a.id = new.related_athlete_id and a.team_id = side_team
  ) then
    raise exception 'the player is not from this team';
  end if;
  return new;
end;
$$;

create trigger game_events_check
before insert or update on public.game_events
for each row execute function private.check_game_event();

-- Soma (p_delta 1) ou tira (-1) um número da súmula do atleta.
create or replace function private.bump_player_stat(
  p_game uuid,
  p_team uuid,
  p_athlete uuid,
  p_field text,
  p_delta integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_athlete is null or p_team is null then
    return;
  end if;
  -- Ao apagar um lance, não cria a linha de quem não estava na súmula.
  if p_delta < 0 and not exists (
    select 1 from public.game_player_stats
    where game_id = p_game and athlete_id = p_athlete
  ) then
    return;
  end if;
  insert into public.game_player_stats (game_id, team_id, athlete_id)
  values (p_game, p_team, p_athlete)
  on conflict (game_id, athlete_id) do nothing;
  if p_field = 'goals' then
    update public.game_player_stats
       set goals = least(greatest(goals + p_delta, 0), 99)
     where game_id = p_game and athlete_id = p_athlete;
  elsif p_field = 'assists' then
    update public.game_player_stats
       set assists = least(greatest(assists + p_delta, 0), 99)
     where game_id = p_game and athlete_id = p_athlete;
  elsif p_field = 'yellow_cards' then
    update public.game_player_stats
       set yellow_cards = least(greatest(yellow_cards + p_delta, 0), 2)
     where game_id = p_game and athlete_id = p_athlete;
  end if;
  -- Vermelho: vale enquanto houver um lance de expulsão do atleta (o
  -- lance apagado já saiu da tabela quando isto roda).
  if p_field = 'red' then
    update public.game_player_stats
       set red_card = exists (
         select 1 from public.game_events e
         where e.game_id = p_game and e.athlete_id = p_athlete
           and e.kind in ('red_card', 'second_yellow')
       )
     where game_id = p_game and athlete_id = p_athlete;
  end if;
end;
$$;

-- Súmula dos atletas a partir de um lance (p_delta 1 ao lançar, -1 ao
-- apagar).
create or replace function private.apply_event_stats(
  e public.game_events,
  p_delta integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  team uuid := private.game_side_team(e.game_id, e.side);
begin
  case e.kind
    when 'goal' then
      perform private.bump_player_stat(e.game_id, team, e.athlete_id, 'goals', p_delta);
      perform private.bump_player_stat(e.game_id, team, e.related_athlete_id, 'assists', p_delta);
    when 'yellow_card' then
      perform private.bump_player_stat(e.game_id, team, e.athlete_id, 'yellow_cards', p_delta);
    when 'second_yellow' then
      perform private.bump_player_stat(e.game_id, team, e.athlete_id, 'yellow_cards', p_delta);
      perform private.bump_player_stat(e.game_id, team, e.athlete_id, 'red', p_delta);
    when 'red_card' then
      perform private.bump_player_stat(e.game_id, team, e.athlete_id, 'red', p_delta);
    when 'substitution' then
      -- Quem entrou jogou (a linha na súmula basta).
      if p_delta > 0 then
        perform private.bump_player_stat(e.game_id, team, e.related_athlete_id, 'none', 0);
        perform private.bump_player_stat(e.game_id, team, e.athlete_id, 'none', 0);
      end if;
    else
      -- Pênalti perdido ou defendido: o atleta jogou.
      if p_delta > 0 then
        perform private.bump_player_stat(e.game_id, team, e.athlete_id, 'none', 0);
      end if;
  end case;
end;
$$;

-- Nome curto para os avisos e a página pública: apelido de quem tem conta,
-- senão o nome cadastrado no time.
create or replace function private.athlete_display_name(p_athlete uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif(pr.nickname, ''), a.name)
  from public.team_players a
  left join public.profiles pr on pr.id = a.profile_id
  where a.id = p_athlete;
$$;

-- Nome de cada lado do jogo.
create or replace function private.game_side_name(g public.games, p_side text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_side = 'host' then private.team_name(g.team_id)
    when g.opponent_team_id is not null then private.team_name(g.opponent_team_id)
    else g.opponent
  end;
$$;

-- Avisa o jogo ao vivo: atletas, técnicos e donos dos dois times e os donos
-- dos times que seguem um deles. Quem fez a ação não recebe.
create or replace function private.notify_live(
  g public.games,
  p_title text,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  person uuid;
begin
  for person in
    select private.team_people(g.team_id)
    union
    select private.team_people(g.opponent_team_id) where g.opponent_team_id is not null
    union
    select private.team_owner(f.follower_team_id)
    from public.team_follows f
    where f.followed_team_id in (g.team_id, g.opponent_team_id)
  loop
    perform private.notify(person, 'live', p_title, p_body, g.team_id, g.id);
  end loop;
end;
$$;

-- "2 × 1" na ordem mandante × visitante (quem marcou primeiro, sem mando).
create or replace function private.live_scoreline(g public.games)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when g.host_is_home is false then
    private.game_side_name(g, 'opponent') || ' ' || coalesce(g.opponent_score, 0)
      || ' × ' || coalesce(g.team_score, 0) || ' ' || private.game_side_name(g, 'host')
  else
    private.game_side_name(g, 'host') || ' ' || coalesce(g.team_score, 0)
      || ' × ' || coalesce(g.opponent_score, 0) || ' ' || private.game_side_name(g, 'opponent')
  end;
$$;

-- Depois de gravar: placar, súmula e aviso de gol.
create or replace function private.apply_game_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.game_events;
  delta integer := case when tg_op = 'DELETE' then -1 else 1 end;
  scorer_side text;
  g public.games;
  scorer text;
  minute text;
begin
  if tg_op = 'DELETE' then
    e := old;
  else
    e := new;
  end if;
  if tg_op = 'UPDATE' then
    -- Completou autor ou assistência: troca na súmula.
    perform private.apply_event_stats(old, -1);
    perform private.apply_event_stats(new, 1);
    return null;
  end if;

  perform private.apply_event_stats(e, delta);

  if e.kind not in ('goal', 'own_goal') then
    return null;
  end if;

  -- Gol: soma no lado de quem fez; gol contra, no outro.
  scorer_side := case
    when e.kind = 'goal' then e.side
    when e.side = 'host' then 'opponent'
    else 'host'
  end;
  update public.games set
    team_score = greatest(coalesce(team_score, 0)
      + case when scorer_side = 'host' then delta else 0 end, 0),
    opponent_score = greatest(coalesce(opponent_score, 0)
      + case when scorer_side = 'opponent' then delta else 0 end, 0)
  where id = e.game_id
  returning * into g;

  -- Jogo de campeonato: a sincronização de games só roda no primeiro nível
  -- de gatilho; daqui, o placar vai direto para o jogo do campeonato (como
  -- em private.sync_game_to_championship).
  if g.championship_match_id is not null then
    -- O aviso do gol já sai daqui: o "Resultado" do campeonato não repete.
    perform set_config('sportleague.live_event', '1', true);
    update public.championship_matches set
      home_score = case when g.host_is_home then g.team_score else g.opponent_score end,
      away_score = case when g.host_is_home then g.opponent_score else g.team_score end,
      home_penalties = null,
      away_penalties = null
    where id = g.championship_match_id;
    perform set_config('sportleague.live_event', '', true);
  end if;

  if tg_op = 'INSERT' and g.id is not null then
    scorer := private.athlete_display_name(e.athlete_id);
    minute := case when e.clock_seconds is null then ''
      else ' aos ' || (e.clock_seconds / 60 + 1) || ''' do '
        || case when e.phase = 'second' then '2º' else '1º' end || ' tempo' end;
    perform private.notify_live(
      g,
      case when e.kind = 'own_goal' then 'Gol contra! '
           else 'Gol do ' || private.game_side_name(g, scorer_side) || '! ' end
        || '⚽',
      coalesce(scorer || case when e.kind = 'own_goal' then ' (contra)' else '' end, 'Gol')
        || minute || '. ' || private.live_scoreline(g) || '.'
    );
  end if;
  return null;
end;
$$;

create trigger game_events_apply
after insert or update of athlete_id, related_athlete_id or delete on public.game_events
for each row execute function private.apply_game_event();

-- Início, intervalo e fim de jogo pelo relógio.
create or replace function private.notify_live_phase()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.match_phase is not distinct from old.match_phase then
    return new;
  end if;
  if old.match_phase is null and new.match_phase = 'first' then
    perform private.notify_live(new, 'Começou! ⏱️',
      private.game_side_name(new, 'host') || ' × '
        || private.game_side_name(new, 'opponent') || ' está rolando.');
  elsif new.match_phase = 'interval' then
    perform private.notify_live(new, 'Intervalo',
      private.live_scoreline(new) || '.');
  elsif new.match_phase = 'finished' then
    perform private.notify_live(new, 'Fim de jogo',
      private.live_scoreline(new) || '.');
  end if;
  return new;
end;
$$;

create trigger games_notify_live_phase
after update of match_phase on public.games
for each row execute function private.notify_live_phase();

-- ---------------------------------------------------------------------------
-- Link público do jogo
-- ---------------------------------------------------------------------------

-- Fora de games: criar o código não passa pelas regras de quem edita o
-- jogo (o adversário e o jogo de campeonato também compartilham).
create table public.game_public_links (
  game_id uuid primary key references public.games (id) on delete cascade,
  code text not null unique check (code ~ '^[a-z0-9]{10}$'),
  created_at timestamptz not null default now()
);

-- Só pelas funções abaixo.
alter table public.game_public_links enable row level security;

-- Código do link público do jogo (cria na primeira vez). O dono ou o
-- técnico de um dos dois times pode compartilhar.
create or replace function public.game_public_link(p_game uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  g public.games;
begin
  if (select auth.uid()) is null then
    raise exception 'Entre na sua conta.';
  end if;
  select * into g from public.games where id = p_game;
  if not found or not (
    private.is_team_staff(g.team_id, (select auth.uid()))
    or (g.opponent_team_id is not null
        and private.is_team_staff(g.opponent_team_id, (select auth.uid())))
  ) then
    raise exception 'Só os times do jogo compartilham o link.';
  end if;
  select code into v_code from public.game_public_links where game_id = p_game;
  if v_code is null then
    loop
      v_code := lower(substr(regexp_replace(
        encode(extensions.gen_random_bytes(16), 'base64'), '[^a-zA-Z0-9]', '', 'g'), 1, 10));
      exit when length(v_code) = 10
        and not exists (select 1 from public.game_public_links where code = v_code);
    end loop;
    insert into public.game_public_links (game_id, code) values (p_game, v_code)
    on conflict (game_id) do nothing;
    select code into v_code from public.game_public_links where game_id = p_game;
  end if;
  return v_code;
end;
$$;

revoke execute on function public.game_public_link(uuid) from public, anon;
grant execute on function public.game_public_link(uuid) to authenticated;

-- Lances de um jogo para as páginas públicas, com o lado do mando.
create or replace function private.public_game_events(p_game uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'kind', e.kind,
    'side', e.side,
    'home', (e.side = 'host') = coalesce(g.host_is_home, true),
    'phase', e.phase,
    'clock_seconds', e.clock_seconds,
    'penalty', e.penalty,
    'athlete', private.athlete_display_name(e.athlete_id),
    'related', private.athlete_display_name(e.related_athlete_id),
    'created_at', e.created_at
  ) order by e.created_at), '[]'::jsonb)
  from public.game_events e
  join public.games g on g.id = e.game_id
  where e.game_id = p_game;
$$;

-- O jogo pelo link público: times, placar, relógio e lances. Sem dados de
-- contato; os atletas aparecem pelo nome no time (ou apelido).
create or replace function public.public_game(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', g.id,
    'scheduled_at', g.scheduled_at,
    'modality', g.modality,
    'type', g.type,
    'status', g.status,
    'host_is_home', g.host_is_home,
    'host', jsonb_build_object(
      'name', private.game_side_name(g, 'host'),
      'logo_url', ht.logo_url
    ),
    'opponent', jsonb_build_object(
      'name', private.game_side_name(g, 'opponent'),
      'logo_url', coalesce(ot.logo_url, gt.logo_url)
    ),
    'team_score', g.team_score,
    'opponent_score', g.opponent_score,
    'match_phase', g.match_phase,
    'clock_started_at', g.clock_started_at,
    'clock_elapsed', g.clock_elapsed,
    'period_minutes', g.period_minutes,
    'server_now', now(),
    'venue', case when v.id is null then null else jsonb_build_object(
      'name', v.name, 'city', v.city, 'state', v.state) end,
    'location', g.location,
    'championship', case when c.id is null then null else jsonb_build_object(
      'name', c.name,
      'public_slug', case when c.public_enabled then c.public_slug end) end,
    'events', private.public_game_events(g.id)
  )
  from public.game_public_links l
  join public.games g on g.id = l.game_id
  left join public.teams ht on ht.id = g.team_id
  left join public.teams ot on ot.id = g.opponent_team_id
  left join public.guest_teams gt on gt.id = g.opponent_guest_id
  left join public.venues v on v.id = g.venue_id
  left join public.championship_matches m on m.id = g.championship_match_id
  left join public.championships c on c.id = m.championship_id
  where l.code = p_code and g.status <> 'canceled';
$$;

revoke execute on function public.public_game(text) from public;
grant execute on function public.public_game(text) to anon, authenticated;

-- Campeonato público: cada jogo traz o relógio e os lances do jogo dos
-- times (quando já começou).
create or replace function private.public_match_live(p_match uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'match_phase', g.match_phase,
    'clock_started_at', g.clock_started_at,
    'clock_elapsed', g.clock_elapsed,
    'period_minutes', g.period_minutes,
    'server_now', now(),
    'events', private.public_game_events(g.id)
  )
  from public.games g
  where g.championship_match_id = p_match
    and (g.match_phase is not null
         or exists (select 1 from public.game_events e where e.game_id = g.id));
$$;

revoke execute on function
  private.game_side_team(uuid, text),
  private.can_add_game_event(uuid, text, public.game_event_kind),
  private.can_edit_game_event(uuid, text),
  private.check_game_event(),
  private.bump_player_stat(uuid, uuid, uuid, text, integer),
  private.apply_event_stats(public.game_events, integer),
  private.athlete_display_name(uuid),
  private.game_side_name(public.games, text),
  private.notify_live(public.games, text, text),
  private.live_scoreline(public.games),
  private.apply_game_event(),
  private.notify_live_phase(),
  private.public_game_events(uuid),
  private.public_match_live(uuid)
from public, anon;
grant execute on function
  private.can_add_game_event(uuid, text, public.game_event_kind),
  private.can_edit_game_event(uuid, text)
to authenticated;


-- O mesmo campeonato público de antes, agora com `live` em cada jogo.
create or replace function public.public_championship(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with c as (
    select * from public.championships
    where public_slug = p_slug and public_enabled
  ),
  entries as (
    select ct.id, ct.name, ct.status, ct.group_label,
           coalesce(t.logo_url, ct.logo_url) as logo_url,
           ct.guest_team_id is not null as guest,
           ct.created_at
    from public.championship_teams ct
    join c on c.id = ct.championship_id
    left join public.teams t on t.id = ct.team_id
    where ct.status <> 'declined'
  ),
  matches as (
    select m.id, m.stage, m.round, m.slot, m.group_label, m.home_id, m.away_id,
           m.scheduled_at, m.home_score, m.away_score,
           m.home_penalties, m.away_penalties,
           v.name as venue_name, v.city as venue_city, v.state as venue_state,
           private.public_match_live(m.id) as live
    from public.championship_matches m
    join c on c.id = m.championship_id
    left join public.venues v on v.id = m.venue_id
  ),
  players as (
    select
      coalesce(nullif(pr.nickname, ''), a.name) as name,
      t.name as team_name,
      t.logo_url,
      sum(s.goals)::integer as goals,
      sum(s.assists)::integer as assists,
      count(*)::integer as games,
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
    'championship', (
      select jsonb_build_object(
        'id', id, 'name', name, 'modality', modality, 'format', format,
        'double_round', double_round, 'group_count', group_count,
        'qualifiers_per_group', qualifiers_per_group, 'team_count', team_count,
        'group_size', group_size, 'knockout_fill', knockout_fill,
        'knockout_qualifiers', knockout_qualifiers,
        'status', status, 'created_at', created_at
      ) from c
    ),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'name', e.name, 'status', e.status,
        'group_label', e.group_label, 'logo_url', e.logo_url, 'guest', e.guest
      ) order by e.created_at) from entries e
    ), '[]'::jsonb),
    'matches', coalesce((
      select jsonb_agg(to_jsonb(m) order by m.stage, m.round, m.slot) from matches m
    ), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.goals desc, p.name) from players p
    ), '[]'::jsonb)
  ) end;
$$;

-- Aviso de resultado do campeonato: o mesmo de antes, mas calado quando o
-- placar mudou por um lance da súmula ao vivo (o aviso do gol já saiu).
create or replace function private.notify_championship_match()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.championships;
  home public.championship_teams;
  away public.championship_teams;
  kind text;
  body text;
  person record;
begin
  if new.home_id is null or new.away_id is null then
    return new;
  end if;
  if new.home_score is not null
     and (old.home_score is distinct from new.home_score
       or old.away_score is distinct from new.away_score
       or old.home_penalties is distinct from new.home_penalties
       or old.away_penalties is distinct from new.away_penalties) then
    if coalesce(current_setting('sportleague.live_event', true), '') = '1' then
      return new;
    end if;
    kind := 'championship_result';
  elsif new.scheduled_at is not null
     and old.scheduled_at is distinct from new.scheduled_at then
    kind := 'championship_match';
  else
    return new;
  end if;

  select * into c from public.championships where id = new.championship_id;
  select * into home from public.championship_teams where id = new.home_id;
  select * into away from public.championship_teams where id = new.away_id;

  if kind = 'championship_result' then
    body := 'Resultado: ' || home.name || ' ' || new.home_score || ' x '
      || new.away_score || ' ' || away.name
      || case when new.home_penalties is null then ''
         else ' (pênaltis ' || new.home_penalties || ' x ' || new.away_penalties || ')'
         end || '.';
  else
    body := 'Jogo marcado: ' || home.name || ' x ' || away.name || ' em '
      || private.game_when(new.scheduled_at)
      || coalesce(' · ' || (select name from public.venues where id = new.venue_id), '')
      || '.';
  end if;

  for person in
    select distinct on (people.profile_id) people.profile_id, people.team_id
    from (
      select private.team_people(t) as profile_id, t as team_id
      from unnest(array_remove(array[home.team_id, away.team_id], null)) as t
    ) people
  loop
    perform private.notify_championship(
      person.profile_id, kind, c.name, body, person.team_id, c.id
    );
  end loop;
  return new;
end;
$$;
