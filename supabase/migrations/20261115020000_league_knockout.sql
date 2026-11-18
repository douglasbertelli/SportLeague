-- Liga + mata-mata: todos jogam entre si (pontos corridos, turno único ou
-- turno e returno) e os primeiros colocados fazem o mata-mata. O
-- organizador escolhe quantos se classificam (2 a 32); quando não fecham 2,
-- 4, 8, 16 ou 32, os melhores colocados folgam na primeira fase. Os jogos da
-- liga ficam com stage 'league' e os do mata-mata com 'knockout', nas fases
-- seguintes às rodadas (o vencedor avança como nos outros formatos).

alter table public.championships
  drop constraint championships_format_check,
  add constraint championships_format_check
    check (format in ('league', 'knockout', 'groups', 'league_knockout')),
  add column knockout_qualifiers smallint
    check (knockout_qualifiers between 2 and 32),
  add constraint championships_league_knockout_options check (
    format <> 'league_knockout' or knockout_qualifiers is not null
  );
