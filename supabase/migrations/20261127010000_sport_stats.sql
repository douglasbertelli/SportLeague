-- Súmula genérica (Etapa 4 do multiesporte, docs/multiesporte-fase1.md).
--
-- O que cada atleta fez no jogo passa a ficar também em
-- `game_player_stats.stats` (jsonb, chave = estatística do esporte), validado
-- pelas estatísticas de cada esporte (`sport_stat_defs`). Tudo aditivo: as
-- colunas do futebol (goals, assists, yellow_cards, red_card) continuam e
-- ficam iguais a `stats` nos dois sentidos, então o app e o site de hoje, os
-- lances ao vivo (bump_player_stat), add_player_goal e as funções de totais
-- continuam funcionando sem mudança. As colunas saem só na fase de limpeza.

-- Esporte de cada modalidade (os jogos são só entre a mesma modalidade, então
-- o esporte do jogo sai dela).
create table public.sport_modalities (
  modality public.team_modality primary key,
  sport public.sport_type not null
);

insert into public.sport_modalities (modality, sport) values
  ('futsal', 'football'),
  ('society', 'football'),
  ('field', 'football'),
  ('beach', 'football'),
  ('challenge', 'football');

alter table public.sport_modalities enable row level security;

create policy "Todos veem as modalidades de cada esporte"
on public.sport_modalities for select
to anon, authenticated
using (true);

-- Estatísticas da súmula de cada esporte. count: 0 até max_value; flag: 0 ou
-- 1 (max_value 1). As mesmas chaves das regras do app e do site.
create table public.sport_stat_defs (
  sport public.sport_type not null,
  key text not null check (key ~ '^[a-z][a-z0-9_]{0,39}$'),
  kind text not null check (kind in ('count', 'flag')),
  max_value smallint not null check (max_value between 1 and 999),
  sort smallint not null default 0,
  primary key (sport, key),
  check (kind = 'count' or max_value = 1)
);

insert into public.sport_stat_defs (sport, key, kind, max_value, sort) values
  ('football', 'goals', 'count', 99, 1),
  ('football', 'assists', 'count', 99, 2),
  ('football', 'yellow_cards', 'count', 2, 3),
  ('football', 'red_card', 'flag', 1, 4);

alter table public.sport_stat_defs enable row level security;

create policy "Todos veem as estatísticas de cada esporte"
on public.sport_stat_defs for select
to anon, authenticated
using (true);

-- Esporte do jogo, pela modalidade; sem modalidade, o futebol.
create or replace function private.game_sport(p_game uuid)
returns public.sport_type
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select sm.sport
       from public.games g
       join public.sport_modalities sm on sm.modality = g.modality
      where g.id = p_game),
    'football'::public.sport_type
  );
$$;
revoke execute on function private.game_sport(uuid) from public, anon;
grant execute on function private.game_sport(uuid) to authenticated;

alter table public.game_player_stats
  add column stats jsonb not null default '{}'::jsonb
  check (jsonb_typeof(stats) = 'object');

-- As linhas de hoje ganham `stats` a partir das colunas (sem mexer no
-- updated_at de cada uma).
alter table public.game_player_stats disable trigger game_player_stats_set_updated_at;
update public.game_player_stats
   set stats = jsonb_build_object(
     'goals', goals,
     'assists', assists,
     'yellow_cards', yellow_cards,
     'red_card', red_card::int
   );
alter table public.game_player_stats enable trigger game_player_stats_set_updated_at;

-- Mantém `stats` e as colunas do futebol iguais e valida `stats`.
-- Quem gravou `stats` (o app e o site novos) vale; senão valem as colunas
-- (app e site antigos, lances ao vivo, add_player_goal).
create or replace function private.sync_player_stats()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sport public.sport_type := private.game_sport(new.game_id);
  v_from_stats boolean;
  v_key text;
  v_value jsonb;
  v_def public.sport_stat_defs;
begin
  if tg_op = 'INSERT' then
    v_from_stats := new.stats <> '{}'::jsonb;
  else
    v_from_stats := new.stats is distinct from old.stats;
  end if;

  if not v_from_stats and v_sport = 'football' then
    new.stats := new.stats || jsonb_build_object(
      'goals', new.goals,
      'assists', new.assists,
      'yellow_cards', new.yellow_cards,
      'red_card', new.red_card::int
    );
  end if;

  for v_key, v_value in select * from jsonb_each(new.stats) loop
    select * into v_def
      from public.sport_stat_defs d
     where d.sport = v_sport and d.key = v_key;
    if not found then
      raise exception 'stat_unknown:%', v_key using errcode = '22023';
    end if;
    if jsonb_typeof(v_value) <> 'number'
       or (v_value #>> '{}')::numeric <> trunc((v_value #>> '{}')::numeric)
       or (v_value #>> '{}')::numeric not between 0 and v_def.max_value then
      raise exception 'stat_invalid:%', v_key using errcode = '22023';
    end if;
  end loop;

  if v_from_stats and v_sport = 'football' then
    new.goals := coalesce((new.stats ->> 'goals')::smallint, 0);
    new.assists := coalesce((new.stats ->> 'assists')::smallint, 0);
    new.yellow_cards := coalesce((new.stats ->> 'yellow_cards')::smallint, 0);
    new.red_card := coalesce((new.stats ->> 'red_card')::int, 0) > 0;
  end if;

  return new;
end;
$$;
revoke execute on function private.sync_player_stats() from public, anon, authenticated;

create trigger game_player_stats_sync_stats
before insert or update on public.game_player_stats
for each row execute function private.sync_player_stats();

-- Soma [p_delta] na estatística [p_key] do atleta (placar ao vivo genérico;
-- add_player_goal continua para o app de hoje). Respeita o máximo do esporte
-- e não fica abaixo de zero. Como add_player_goal, roda com a permissão de
-- quem chama (a RLS da súmula decide).
create or replace function public.add_player_stat(
  p_game uuid,
  p_team uuid,
  p_athlete uuid,
  p_key text,
  p_delta integer default 1
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_max smallint;
begin
  select d.max_value into v_max
    from public.sport_stat_defs d
   where d.sport = private.game_sport(p_game) and d.key = p_key;
  if v_max is null then
    raise exception 'stat_unknown:%', p_key using errcode = '22023';
  end if;

  insert into public.game_player_stats (game_id, team_id, athlete_id)
  values (p_game, p_team, p_athlete)
  on conflict (game_id, athlete_id) do nothing;

  update public.game_player_stats
     set stats = stats || jsonb_build_object(
       p_key,
       least(greatest(coalesce((stats ->> p_key)::int, 0) + p_delta, 0), v_max)
     )
   where game_id = p_game and athlete_id = p_athlete;
end;
$$;
revoke execute on function public.add_player_stat(uuid, uuid, uuid, text, integer) from public, anon;
grant execute on function public.add_player_stat(uuid, uuid, uuid, text, integer) to authenticated;
