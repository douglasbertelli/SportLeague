# Multiesporte — Fase 2: vôlei

## Objetivo

Liberar o **vôlei** no SportLeague (app Flutter, `sportleague-web` e banco),
usando a base da Fase 1 (`docs/multiesporte-fase1.md`): regras do esporte
num lugar só, súmula genérica (`stats`) e esporte ligado à modalidade.

**Critério de pronto:** um administrador cria um time de vôlei, marca
amistosos e campeonatos contra outros times de vôlei, lança o placar em sets
e a súmula, e vê a classificação e os rankings do vôlei. O futebol continua
igual.

## Decisões

| Tema | Decisão |
|---|---|
| Modalidades | **Quadra** (6x6) e **Praia** (dupla, 2x2), novas e só do vôlei. A "Areia" de hoje continua sendo do futebol. |
| Partida | Quem marca escolhe **melhor de 3 ou de 5** sets. Sets de **25** pontos e tie-break de **15**; na praia, **21** e **15**. Sempre com **2 pontos de diferença**. Sem empate. |
| Súmula | **Pontos, aces e bloqueios** de cada atleta, mais quem jogou e o craque. Rankings: maiores pontuadores, aces e bloqueios. |
| Classificação | **Padrão CBV/FIVB**: vitória por 3x0/3x1 (ou 2x0) vale 3 pontos; 3x2 (ou 2x1) vale 2 para quem vence e 1 para quem perde. Desempate: vitórias, saldo de sets e saldo de pontos. |
| Relógio | O vôlei **não tem relógio**: o placar ao vivo é por set. |
| Escalação | Titulares: 6 na quadra, 2 na praia. Sem a escalação desenhada no campo. |
| Posições | Levantador, Oposto, Ponteiro, Central e Líbero. Na praia não há posição fixa: Bloqueador e Defensor. |

## Riscos

1. **Apps já instalados quebram com vôlei.** O app lê modalidade e esporte
   com `firstWhere` (`Modality.fromName`, `Sport.fromName`), que gera um
   erro com um valor desconhecido. Assim que existir um time de vôlei, um app
   de hoje que o receba (na busca de times, como adversário, num campeonato,
   num seguidor) mostra erro. Por isso a **Etapa 0** vem antes de tudo: as
   versões novas passam a aceitar valores desconhecidos, e o vôlei só é
   liberado com a **versão mínima** obrigatória.
2. **Valores novos de enum no banco.** `alter type … add value` não pode
   ser usado na mesma transação em que foi criado. Os valores novos ficam
   numa migration própria, antes da que os usa.
3. **Placar em sets mexe no que já existe.** `games.team_score` /
   `opponent_score` e `championship_matches.home_score` / `away_score`
   passam a ser **sets vencidos** no vôlei. As funções que só comparam os
   dois números (vitória, derrota, classificação, avanço do mata-mata)
   continuam certas. As que somam gols (gols pró/contra, saldo) precisam das
   regras do esporte.

## Etapas

Cada etapa é um PR (no app, no site ou nos dois). Até a Etapa 7, nada do
vôlei aparece para o usuário.

### Etapa 0 — Apps preparados para outros esportes

- `Modality.fromName` e `Sport.fromName` deixam de quebrar com valor
  desconhecido. Times, jogos, campeonatos e adversários de um esporte que o
  app não conhece ficam de fora das listas.
- **Versão mínima**: tabela `app_config` com `min_build` por plataforma,
  lida na abertura do app. Abaixo dela, uma tela pede para atualizar, com o
  link da loja. Serve também para a fase de limpeza da Fase 1.
- Publicar esta versão nas lojas o quanto antes, para que ela esteja
  instalada quando o vôlei for liberado.

> **Como ficou:** `Sport.tryFromName` / `Modality.tryFromName`; o que vem do
> banco nunca passa por um `fromName` que quebre. As listas de times (meus,
> como técnico e jogador, busca, convites, adversários), campeonatos e
> fictícios usam `isSupportedSportRow` / `isSupportedModalityRow` (esportes
> de `supportedSports`); abrir um campeonato de outro esporte mostra
> "Atualize o app na loja". Versão mínima: tabela `app_versions`
> (`20261127030000_app_versions.sql`, `min_build` 0 nas duas plataformas,
> link da Play Store; o da App Store fica nulo até existir) e a rota
> `/update-required`, que vem antes de tudo, com ou sem login. Sem rede, sem
> linha ou fora do Android e do iOS, o app não bloqueia. Para exigir uma
> versão: `update public.app_versions set min_build = <build> where platform
> = 'android';` no SQL Editor.

### Etapa 1 — Regras do vôlei (app e site, sem liberar)

- `volleyballRules` no `SportRules` (app) e no `rules.ts` (site), com as
  decisões acima.
- As regras ganham o **placar em sets**: `SetRules` (opções de melhor de,
  pontos por set e do tie-break por modalidade, diferença mínima) e a
  pontuação da classificação pelo resultado em sets (`StandingsRules` com
  3/2/1/0 e os desempates `setDifference` e `pointDifference`).
- `Modality` ganha `volleyballIndoor` ("Quadra") e `volleyballBeach`
  ("Praia"). `supportedSports` continua só com o futebol.
- Testes das regras: quem venceu cada set, quem venceu a partida, set
  inválido (25x24, 26x25 sem 2 de diferença) e pontuação 3/2/1/0.

> **Como ficou:** no app, `Modality.volleyballIndoor` / `volleyballBeach`
> com a chave do banco (`Modality.key`: `volleyball_indoor`,
> `volleyball_beach`; as do futebol continuam com o nome), e tudo que grava
> ou consulta modalidade passou a usar `key`. `SetRules` (`setsToWin`,
> `targetFor`, `isFinishedSet`, `matchResult`, `isClose`),
> `StandingsRules.closeWin` / `closeLoss` (no futebol, iguais a vitória e
> derrota) e o desempate `pointDifference` (por enquanto vale 0 na
> classificação; entra de verdade na Etapa 5). `positionsFor(modality)`:
> na praia, Bloqueador e Defensor. `rulesFor(Sport.volleyball)` devolve
> `volleyballRules`, mas `supportedSports` continua só com o futebol. O
> título da súmula passou a usar a unidade da estatística que soma no placar
> ("pontos"), e não a do placar ("sets"). No site, o mesmo em `rules.ts`
> (`matchResult`, `setTarget`, `isFinishedSet`, `isCloseResult`,
> `positionsFor`). Um set no tie-break que vai para a vantagem (25x23)
> vale: passou do alvo com a diferença exata de 2.

### Etapa 2 — Banco: modalidades, súmula e sets do vôlei (aditiva)

- Migration A: `team_modality` ganha `volleyball_indoor` e
  `volleyball_beach`.
- Migration B:
  - `sport_modalities` passa a ter as duas modalidades novas;
  - `sport_stat_defs` do vôlei: `points`, `aces`, `blocks` (até 99);
  - `games.best_of` e `championships.best_of` (3 ou 5, só no vôlei);
  - `games.set_scores` e `championship_matches.set_scores` (jsonb, lista
    de `[time, adversário]` / `[mandante, visitante]`);
  - gatilho que valida os sets pelas regras (pontos por set, tie-break,
    diferença de 2, a partida acaba quando alguém fecha os sets) e grava
    `team_score`/`opponent_score` como sets vencidos;
  - a sincronia jogo ↔ jogo de campeonato (`sync_championship_game`,
    `sync_game_to_championship`) leva os sets junto;
  - `advance_knockout` continua pelo placar (sets), sem pênaltis no vôlei.
- Testada num bloco desfeito no banco, como na Fase 1.

> **Como ficou** (`20261127040000_volleyball_modalities.sql` e
> `20261127050000_volleyball_sets.sql`): as regras de sets ficam na tabela
> `modality_set_rules` (pontos por set, tie-break, diferença mínima e melhor
> de padrão por modalidade), lida por `private.sets_result`, que confere os
> sets e devolve os vencidos de cada lado; a partida pode estar em andamento
> (ninguém venceu ainda), mas cada set lançado precisa estar terminado. Os
> gatilhos `games_apply_sets` (roda antes de `games_check_score`, que
> continua conferindo o horário do placar), `championship_matches_apply_sets`
> e `championships_apply_best_of` gravam o placar pelos sets, põem o melhor
> de padrão e recusam sets no futebol, placar sem sets e pênaltis no vôlei.
> O time do jogo de campeonato pode lançar `set_scores` (lista de colunas
> editáveis de `check_championship_game`), e a sincronia nos dois sentidos
> leva os sets, invertendo quando o time do jogo é o visitante
> (`private.flip_sets`). A migration A precisou ser aplicada antes do teste
> da B (valores novos de enum não podem ser usados na mesma transação).

### Etapa 3 — Totais pela súmula genérica (banco)

As funções de totais passam a devolver também `stats` (soma por chave),
sem tirar os campos de hoje: `team_player_totals`, `my_player_totals`,
`championship_player_totals`, `public_profile`, `public_championship`,
`private.championship_stats_data` e `team_profile_stats`. Esta última
devolve também os sets e pontos pró/contra.

> **Como ficou** (`20261127060000_stats_totals.sql`): o agregador
> `private.jsonb_sum` soma o `stats` chave por chave, e `private.set_points`
> soma os pontos de cada lado nos sets. As três funções que devolvem tabela
> (`team_player_totals`, `my_player_totals`, `championship_player_totals`)
> foram recriadas com a coluna `stats` no fim (mudar o formato da saída
> exige `drop`), com as mesmas permissões. As que devolvem JSON ganharam
> `stats` nos jogadores, totais, carreira e por time; os sets
> (`set_scores`) nos últimos jogos e nos jogos do campeonato público; o
> melhor de no campeonato público; e `points_for` / `points_against` no
> perfil do time (0 no futebol). Testada num bloco desfeito que guardou a
> saída de todas as funções antes, aplicou e conferiu que a saída depois,
> sem os campos novos, era idêntica (5 times, 1 jogador, 1 campeonato, 3
> perfis públicos), e que `stats` bate com as colunas do futebol.

### Etapa 4 — Placar em sets (app e site)

- Formulário do amistoso: melhor de 3 ou de 5 (só no vôlei).
- Lançar o placar em sets, contestar o placar em sets, e o card do jogo
  com "3 x 1 (25-20, 23-25, 25-18, 25-22)".
- Placar ao vivo do vôlei: pontos do set atual, "Encerrar set" e o placar
  em sets. Sem relógio nem apito.
- Imagem compartilhada do resultado e banner com os sets.

> **Como ficou:** o placar ao vivo é **set a set** (decisão: o ponto a ponto
> fica para depois de liberar o vôlei). Quem marcou lança cada set quando ele
> termina; `SetRules.progress` (app) e `setsProgress` (site) aceitam a
> partida em andamento, e o placar depois do jogo exige a partida terminada.
> No app: `Game.bestOf` / `setScores` (com `setScoresFor` e `setsLabelFor`
> na visão de quem olha), `GameRepository.setSets`, a tela
> `sets_sheet.dart` (lançar sets e o placar ao vivo `LiveSetsScore`), o card
> "Jogo em andamento" sem relógio nem lances no vôlei, "Sets: 25-20, …" no
> card e na imagem compartilhada, e "Partida: melhor de 3 / 5" no
> formulário do amistoso. No site: `SetsForm`, a ação `setSets`, os sets no
> card e na página do jogo, o melhor de no formulário e as mensagens dos
> erros de sets. **A contestação do placar fica desligada no vôlei** (ela é
> em gols; aceitar uma contestação gravaria o placar sem sets, que o banco
> recusa) e o banner continua sem os sets: os dois ficam para depois.

### Etapa 5 — Campeonato do vôlei (app e site)

- Criar campeonato de vôlei com melhor de 3 ou de 5.
- Lançar o placar dos jogos em sets; classificação 3/2/1/0 com saldo de
  sets e de pontos; mata-mata sem pênaltis.
- Suspensões por cartão ficam desligadas no vôlei.

> **Como ficou:** `Championship.bestOf` e `ChampionshipMatch.setScores`
> (com os pontos de cada lado nos sets). O organizador lança os sets com a
> tela de sets, que ficou genérica (`showSetsEditor`, usada também pelo jogo
> do time), exigindo a partida terminada; o mata-mata avança pelo placar em
> sets e não pede pênaltis. A classificação conta as vitórias e derrotas
> "apertadas" (vencidas por um só: no vôlei, o tie-break) e os pontos dentro
> dos sets, então o 3/2/1/0 e o desempate por saldo de pontos saem das
> regras; no futebol, apertado vale igual (`closeWin = win`). A tabela do
> vôlei não tem a coluna de empates e usa SP / SC / SS (sets) no lugar de
> GP / GC / SG, no app, na imagem compartilhada e no site. O formulário do
> campeonato escolhe melhor de 3 ou 5 e esconde a suspensão por cartão
> (gravada como 0). No site, a função de classificação não roda direto nos
> testes do Node (importa arquivos sem extensão); a pontuação e o desempate
> estão cobertos pelos testes de `rules.ts`.

### Etapa 6 — Súmula e rankings do vôlei (app e site)

- Súmula do vôlei com pontos, aces e bloqueios.
- Meus números, perfil do atleta, rankings do time, aba de estatísticas do
  campeonato e páginas públicas (`/p`, `/c`) lendo `stats` pelas regras.
- A aba de estatísticas do campeonato e as páginas públicas, que ficaram
  de fora da Fase 1, passam a ler as regras também no futebol.

> **Como ficou:** a linha da súmula e os totais guardam as estatísticas que
> não são colunas do futebol (`extra` no app, `stats` no site) e a súmula
> grava só as chaves do esporte do jogo (o banco recusa as de outro). Os
> quadros de números usam as regras do esporte do time: perfil do atleta,
> Meus números (no Geral, as do esporte dos times, se forem todos do mesmo)
> e a lista de atletas do site, que ganhou a tabela pelas regras. A aba de
> estatísticas do campeonato (app e site) tem um ranking por estatística do
> esporte (no futebol, Artilharia e Assistências, como antes; no vôlei,
> Pontuadores, Aces e Bloqueios), e cartões e fair play só aparecem nos
> esportes com cartão; o "melhor ataque" conta sets no vôlei. A página
> pública do campeonato usa o primeiro ranking do esporte. Mudou um texto no
> futebol: a aba vazia do app diz "O ranking vem da súmula dos jogos." **O
> perfil público do jogador (`/p`) continua do futebol**: ele soma times que
> podem ser de esportes diferentes e pede um desenho próprio (fica para
> depois).

### Etapa 7 — Liberar o vôlei

- `supportedSports` ganha o vôlei (app e site). O cadastro do time no site
  ganha a escolha do esporte (no app ela já existe e aparece sozinha).
- Versão mínima (Etapa 0) passa a exigir a versão com o vôlei.
- Textos das lojas, do site de apresentação (`sportleague-site`) e dos
  Termos, se citarem só o futebol.
- Roteiro manual completo com dois times de vôlei e um de futebol.

## Verificação de cada PR

- `flutter analyze`, `flutter test`, `npm test`, `tsc`, `lint` e
  `npm run build` passando, sem alterar os testes antigos.
- Migrations testadas num bloco desfeito no banco antes de aplicar, e
  aplicadas só com confirmação.
- O futebol continua igual: os testes da Fase 1 conferem os valores e
  textos de antes.
