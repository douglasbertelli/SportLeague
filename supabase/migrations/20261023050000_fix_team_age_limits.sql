-- Correção da 20261023040000_team_age_limits: com as idades vazias, o
-- "between" dá nulo e a regra passava (um check nulo é aceito). Agora Base
-- exige as duas idades e Master a mínima.

alter table public.teams drop constraint teams_age_limits;

alter table public.teams
  add constraint teams_age_limits check (
    case age_group
      when 'open' then min_age is null and max_age is null
      when 'youth' then min_age is not null
        and max_age is not null
        and min_age between 3 and 25
        and max_age between min_age and 25
      when 'master' then min_age is not null
        and max_age is null
        and min_age between 30 and 80
      else false
    end
  );
