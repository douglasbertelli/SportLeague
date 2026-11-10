-- O dono renomeia o time fictício (aba Fictícios de Meus times): os
-- amistosos ainda por jogar passam a mostrar o nome novo. Os já jogados ou
-- cancelados ficam com o nome da época. As inscrições nos campeonatos já
-- acompanhavam (sync_guest_team_entries).

create or replace function private.sync_guest_team_games()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.games
  set opponent = new.name
  where opponent_guest_id = new.id
    and status in ('pending', 'scheduled')
    and opponent is distinct from new.name;
  return new;
end;
$$;

revoke execute on function private.sync_guest_team_games() from public, anon;

create trigger guest_teams_sync_games
after update of name on public.guest_teams
for each row
when (new.name is distinct from old.name)
execute function private.sync_guest_team_games();
