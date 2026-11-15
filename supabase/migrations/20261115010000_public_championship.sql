-- Campeonato público: o organizador liga quando quiser e compartilha um link
-- com código aleatório (/c/<código>) para quem não tem conta acompanhar a
-- classificação, os jogos e a artilharia. Desligado, o link não mostra
-- nada; trocar o código derruba o link antigo.
alter table public.championships
  add column if not exists public_enabled boolean not null default false,
  add column if not exists public_slug text unique;

-- Liga ou desliga o link público do campeonato (só o organizador); com
-- p_new_link, troca o código. Devolve o código atual.
create or replace function public.set_championship_public(
  p_championship uuid,
  p_enabled boolean,
  p_new_link boolean default false
)
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
  select public_slug into v_slug
  from public.championships
  where id = p_championship and owner_id = (select auth.uid());
  if not found then
    raise exception 'Só o organizador muda o link público do campeonato.';
  end if;
  if v_slug is null or p_new_link then
    loop
      v_slug := lower(substr(translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=', ''), 1, 10));
      exit when not exists (select 1 from public.championships where public_slug = v_slug);
    end loop;
  end if;
  update public.championships
     set public_enabled = p_enabled, public_slug = v_slug
   where id = p_championship;
  return v_slug;
end;
$$;

revoke all on function public.set_championship_public(uuid, boolean, boolean) from public, anon;
grant execute on function public.set_championship_public(uuid, boolean, boolean) to authenticated;

-- Tudo o que a página pública mostra, para qualquer visitante (sem login).
-- Nulo se o código não existe ou o link está desligado. Só o campeonato, os
-- times inscritos (nome, logo e grupo), os jogos (data, local e placar) e a
-- artilharia (nome no time, sem conta nem contato). Nunca devolve o dono,
-- e-mails, telefones, endereço do local nem ids de perfis.
create or replace function public.public_championship(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path to ''
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
           v.name as venue_name, v.city as venue_city, v.state as venue_state
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

revoke all on function public.public_championship(text) from public;
grant execute on function public.public_championship(text) to anon, authenticated;
