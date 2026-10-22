-- Amistoso contra um time da plataforma aparece para os dois times: o dono e
-- os atletas do time que marcou e do time adversário. Só quem marcou altera ou
-- exclui (políticas de insert/update/delete continuam pelo team_id).

drop policy "Dono e atletas do time veem os jogos" on public.games;

create policy "Os dois times veem o amistoso"
on public.games for select
to authenticated
using (
  private.is_team_owner(games.team_id, (select auth.uid()))
  or (
    games.opponent_team_id is not null
    and private.is_team_owner(games.opponent_team_id, (select auth.uid()))
  )
  or exists (
    select 1 from public.team_players p
    where p.profile_id = (select auth.uid())
      and (p.team_id = games.team_id or p.team_id = games.opponent_team_id)
  )
);
