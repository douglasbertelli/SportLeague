-- Faixa de idade com os limites escolhidos pelo administrador:
--   Livre:  sem limites;
--   Base:   idade mínima e máxima (entre 3 e 25 anos), ex.: sub-15 = 13 a 15;
--   Master: idade mínima (entre 30 e 80 anos), ex.: 35 ou 40.
-- Times que já eram Base ou Master ficam com os limites antigos (4 a 20 e 35).

alter table public.teams
  add column min_age smallint,
  add column max_age smallint;

update public.teams set min_age = 4, max_age = 20 where age_group = 'youth';
update public.teams set min_age = 35 where age_group = 'master';

alter table public.teams
  add constraint teams_age_limits check (
    (age_group = 'open' and min_age is null and max_age is null)
    or (age_group = 'youth'
        and min_age between 3 and 25
        and max_age between min_age and 25)
    or (age_group = 'master'
        and min_age between 30 and 80
        and max_age is null)
  );
