-- Perfil público: a pessoa liga quando quiser e compartilha um link com
-- código aleatório (/p/<código>). Desligado, o link não mostra nada.
alter table public.profiles
  add column if not exists public_enabled boolean not null default false,
  add column if not exists public_slug text unique;

-- Liga ou desliga o perfil público; com p_new_link, troca o código (o link
-- antigo para de funcionar). Devolve o código atual.
create or replace function public.set_public_profile(p_enabled boolean, p_new_link boolean default false)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_slug text;
begin
  if (select auth.uid()) is null then
    raise exception 'Entre na sua conta.';
  end if;
  select public_slug into v_slug from public.profiles where id = (select auth.uid());
  if v_slug is null or p_new_link then
    loop
      v_slug := lower(substr(translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=', ''), 1, 10));
      exit when not exists (select 1 from public.profiles where public_slug = v_slug);
    end loop;
  end if;
  update public.profiles
     set public_enabled = p_enabled, public_slug = v_slug
   where id = (select auth.uid());
  return v_slug;
end;
$$;

revoke all on function public.set_public_profile(boolean, boolean) from public, anon;
grant execute on function public.set_public_profile(boolean, boolean) to authenticated;

-- Tudo o que a página pública mostra, para qualquer visitante (sem login).
-- Nulo se o código não existe, o perfil está desligado ou a conta foi
-- excluída. Nunca devolve telefone, e-mail, data de nascimento nem o código
-- de convite.
create or replace function public.public_profile(
  p_slug text,
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  with me as (
    select p.*
    from public.profiles p
    where p.public_slug = p_slug
      and p.public_enabled
      and p.deleted_at is null
  ),
  -- Fichas de atleta da pessoa nos times ativos.
  athletes as (
    select a.id, a.team_id, a.jersey_number, a.position, a.inactive_at
    from public.team_players a
    join me on me.id = a.profile_id
    join public.teams t on t.id = a.team_id and t.inactive_at is null
  ),
  -- Jogos realizados (válidos) em que a pessoa entrou na súmula.
  stats as (
    select s.*, g.scheduled_at
    from public.game_player_stats s
    join athletes a on a.id = s.athlete_id
    join public.games g on g.id = s.game_id
    where g.status = 'scheduled' and g.scheduled_at <= now()
  ),
  season_stats as (
    select * from stats
    where (p_from is null or scheduled_at >= p_from)
      and (p_to is null or scheduled_at < p_to)
  ),
  -- Times: os que administra, treina e em que joga.
  teams as (
    select t.id, t.name, t.logo_url, t.city, t.state, 'admin' as relation, null::smallint as jersey_number, null::text as position
    from public.teams t join me on me.id = t.owner_id
    where t.inactive_at is null
    union all
    select t.id, t.name, t.logo_url, t.city, t.state, 'coach', null, null
    from public.team_coaches c
    join me on me.id = c.profile_id
    join public.teams t on t.id = c.team_id and t.inactive_at is null
    union all
    select t.id, t.name, t.logo_url, t.city, t.state, 'player', a.jersey_number, a.position
    from athletes a join public.teams t on t.id = a.team_id
    where a.inactive_at is null
  ),
  totals as (
    select
      count(*) as games,
      coalesce(sum(goals), 0) as goals,
      coalesce(sum(assists), 0) as assists,
      coalesce(sum(yellow_cards), 0) as yellow_cards,
      count(*) filter (where red_card) as red_cards,
      count(*) filter (where best_player) as best_player
    from season_stats
  ),
  career as (
    select
      count(*) as games,
      coalesce(sum(goals), 0) as goals,
      coalesce(sum(assists), 0) as assists,
      count(*) filter (where best_player) as best_player
    from stats
  )
  select case when not exists (select 1 from me) then null else jsonb_build_object(
    'name', (select coalesce(nullif(nickname, ''), full_name) from me),
    'full_name', (select full_name from me),
    'role', (select role from me),
    'age', (select extract(year from age(birth_date))::int from me where birth_date is not null),
    'position', (select preferred_position from me),
    'foot', (select preferred_foot from me),
    'height_cm', (select height_cm from me),
    'avatar_url', (select avatar_url from me),
    'cover_url', (select cover_url from me),
    'member_since', (select created_at from me),
    'teams', coalesce((select jsonb_agg(t order by t.relation, t.name) from teams t), '[]'::jsonb),
    'totals', (select to_jsonb(t) from totals t),
    'career', (select to_jsonb(c) from career c),
    -- Números da temporada em cada time em que joga.
    'by_team', coalesce((
      select jsonb_agg(x order by x.games desc, x.team_name)
      from (
        select t.id as team_id, t.name as team_name, t.logo_url as team_logo_url,
               count(s.game_id) as games,
               coalesce(sum(s.goals), 0) as goals,
               coalesce(sum(s.assists), 0) as assists,
               coalesce(sum(s.yellow_cards), 0) as yellow_cards,
               count(*) filter (where s.red_card) as red_cards,
               count(*) filter (where s.best_player) as best_player
        from athletes a
        join public.teams t on t.id = a.team_id
        left join season_stats s on s.athlete_id = a.id
        group by t.id
      ) x
    ), '[]'::jsonb),
    -- Últimos jogos da pessoa, com o placar do time dela.
    'recent', coalesce((
      select jsonb_agg(r order by r.scheduled_at desc)
      from (
        select g.scheduled_at, s.goals, s.assists, s.best_player, s.yellow_cards, s.red_card,
               t.name as team_name, t.logo_url as team_logo_url,
               case when g.team_id = s.team_id then g.opponent else coalesce(h.name, 'Time') end as opponent,
               case when g.team_id = s.team_id then o.logo_url else h.logo_url end as opponent_logo_url,
               case when g.team_id = s.team_id then g.team_score else g.opponent_score end as goals_for,
               case when g.team_id = s.team_id then g.opponent_score else g.team_score end as goals_against
        from season_stats s
        join public.games g on g.id = s.game_id
        join public.teams t on t.id = s.team_id
        left join public.teams h on h.id = g.team_id
        left join public.teams o on o.id = g.opponent_team_id
        order by g.scheduled_at desc
        limit 8
      ) r
    ), '[]'::jsonb),
    -- Campanha dos times que administra ou treina, na temporada.
    'team_records', coalesce((
      select jsonb_agg(
        jsonb_build_object('team_id', t.id, 'team_name', t.name, 'team_logo_url', t.logo_url, 'relation', t.relation)
        || (public.team_profile_stats(t.id, p_from, p_to) - 'upcoming' - 'followers' - 'following')
        order by t.name
      )
      from (select distinct on (id) * from teams where relation in ('admin', 'coach') order by id, relation) t
    ), '[]'::jsonb)
  ) end;
$$;

revoke all on function public.public_profile(text, timestamptz, timestamptz) from public;
grant execute on function public.public_profile(text, timestamptz, timestamptz) to anon, authenticated;
