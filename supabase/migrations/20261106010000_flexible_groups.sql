-- Grupos + mata-mata flexível: o organizador escolhe quantos times o
-- campeonato tem, o máximo de times por grupo (o app calcula os grupos, o
-- mais parelho possível) e quantos passam de cada grupo. Quando os
-- classificados não fecham 2, 4, 8, 16 ou 32, escolhe como completar o
-- mata-mata: com os melhores colocados da posição seguinte ou com folga para
-- os melhores classificados. Até 16 grupos (A a P).

alter table public.championships
  add column team_count smallint check (team_count between 4 and 64),
  add column group_size smallint check (group_size between 2 and 32),
  add column knockout_fill text check (knockout_fill in ('best_placed', 'byes'));

alter table public.championships
  drop constraint championships_group_count_check,
  add constraint championships_group_count_check
    check (group_count between 2 and 16),
  drop constraint championships_qualifiers_per_group_check,
  add constraint championships_qualifiers_per_group_check
    check (qualifiers_per_group between 1 and 31);

alter table public.championship_teams
  drop constraint championship_teams_group_label_check,
  add constraint championship_teams_group_label_check
    check (group_label ~ '^[A-P]$');

alter table public.championship_matches
  drop constraint championship_matches_group_label_check,
  add constraint championship_matches_group_label_check
    check (group_label ~ '^[A-P]$');

-- Os campeonatos com grupos que já existem: os times confirmados.
update public.championships c
set team_count = greatest(4, least(64, (
      select count(*) from public.championship_teams t
      where t.championship_id = c.id and t.status <> 'declined'
    ))),
    group_size = greatest(2, ceil((
      select count(*) from public.championship_teams t
      where t.championship_id = c.id and t.status <> 'declined'
    )::numeric / c.group_count)::int)
where c.format = 'groups' and c.team_count is null;
