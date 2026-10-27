-- Dois atletas do mesmo time não podem ter o mesmo número de camisa (sem
-- número, pode).
create unique index team_players_unique_number
  on public.team_players (team_id, jersey_number)
  where jersey_number is not null;
