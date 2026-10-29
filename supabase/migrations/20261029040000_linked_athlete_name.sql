-- Atleta vinculado a uma conta de jogador: o nome mostrado vem do perfil dele
-- (apelido ou, sem ele, o nome completo) e só o próprio jogador altera. O
-- administrador continua editando número, posição e foto, mas o nome
-- cadastrado no time não muda mais depois do vínculo.
create or replace function private.keep_linked_athlete_name()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.profile_id is not null and new.name is distinct from old.name then
    new.name := old.name;
  end if;
  return new;
end;
$$;

revoke execute on function private.keep_linked_athlete_name() from public, anon;

create trigger team_players_keep_linked_name
before update on public.team_players
for each row execute function private.keep_linked_athlete_name();

-- Artilharia, garçons e números do atleta: do vinculado, o apelido ou o nome
-- do perfil; do atleta sem conta, o nome cadastrado no time.
create or replace function public.team_player_totals(
  p_team uuid,
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null
)
returns table (
  athlete_id uuid,
  name text,
  jersey_number smallint,
  "position" text,
  games bigint,
  goals bigint,
  assists bigint,
  yellow_cards bigint,
  red_cards bigint,
  best_player bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    a.id,
    coalesce(p.nickname, p.full_name, a.name),
    a.jersey_number,
    a.position,
    count(s.game_id),
    coalesce(sum(s.goals), 0),
    coalesce(sum(s.assists), 0),
    coalesce(sum(s.yellow_cards), 0),
    count(*) filter (where s.red_card),
    count(*) filter (where s.best_player)
  from public.team_players a
  left join public.profiles p on p.id = a.profile_id
  left join public.game_player_stats s on s.athlete_id = a.id
    and exists (
      select 1 from public.games g
      where g.id = s.game_id
        and g.status = 'scheduled'
        and (p_from is null or g.scheduled_at >= p_from)
        and (p_to is null or g.scheduled_at < p_to)
    )
  where a.team_id = p_team
  group by a.id, p.nickname, p.full_name
  order by 2;
$$;
