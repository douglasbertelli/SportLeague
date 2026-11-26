# Multiesporte — Fase 1: regras por esporte, sem mudar o futebol

## Objetivo

Preparar o SportLeague (app Flutter, `sportleague-web` e banco Supabase) para
receber outros esportes. Ao final, cada regra que hoje está escrita pensando no
futebol passa a vir de um lugar só: as **regras do esporte**.

**Critério de pronto:** para quem usa, o futebol continua **igual**: mesmas
telas, mesmos números, mesmas notificações, no app e no web. Nenhum esporte
novo aparece para o usuário nesta fase.

Vôlei e basquete são a Fase 2 e a Fase 3. Esta fase só deixa o terreno pronto.

## Ponto de partida

- O esporte já existe: `public.sport_type` (`football`, `volleyball`,
  `basketball`) e `teams.sport` (padrão `football`) no banco, e o enum `Sport`
  em `lib/features/teams/domain/team.dart`. Nada lê esse campo, e o cadastro
  do time sempre grava `Sport.football`.
- As modalidades (`team_modality`: futsal, society, field, beach, challenge)
  são todas de futebol. Como amistosos e campeonatos já exigem a **mesma
  modalidade**, se cada esporte tiver modalidades próprias, a regra atual já
  impede um jogo entre esportes diferentes, sem nenhuma regra nova.
- As regras de futebol estão espalhadas:

| Regra | Onde está hoje |
|---|---|
| Duração de cada tempo | `MatchClock.defaultPeriodMinutes` (`games/domain/match_clock.dart`) |
| Fases da partida | enum `MatchPhase` + tipo `match_phase` + `game_clock()` |
| Titulares por modalidade | `startersFor` (`games/data/lineup_repository.dart`) |
| Formações e siglas | `games/domain/formation.dart`, `tactical_lineup.dart`, `game_lineups.slot` 0–10 |
| Posições do atleta | lista em `athletes/domain/athlete.dart` |
| Súmula | colunas `goals`, `assists`, `yellow_cards`, `red_card`, `best_player` em `game_player_stats` |
| Totais e rankings | `team_player_totals`, `my_player_totals`, `championship_player_totals`, `public_profile`, `public_championship` |
| Classificação | `championship_rules.dart` (`wins * 3 + draws`, saldo de gols) |
| Desempate do mata-mata | `home_penalties` / `away_penalties`, `advance_knockout()` |
| V/E/D do time | `team_stats.dart`, `team_profile_stats()` |
| Gol no placar ao vivo | `add_player_goal()` |

## Antes de começar

1. **Juntar as branches abertas.** `SportLeague-sumula`
   (`feature/live-scoresheet`) e `SportLeague-camp`
   (`feature/championship-plus`) mexem justamente na súmula e nos campeonatos.
   Fazer o merge delas antes da Etapa 4, ou rebasear a Fase 1 por cima delas.
   Conferir também em que estão `SportLeague-mural`, `SportLeague-caixa` e
   `sportleague-web-sumula`.
2. **Versões antigas do app.** Não encontrei bloqueio de versão mínima no app.
   Quem não atualizar continua lendo e gravando as colunas antigas da súmula
   e recebendo os campos antigos das funções SQL. Por isso, toda mudança no
   banco desta fase é **aditiva**: o antigo continua funcionando até a Fase de
   limpeza (no fim deste documento). Vale aproveitar e criar o aviso de
   "atualize o app" (Etapa 0).
3. **O web usa o mesmo banco.** O `sportleague-web` lê e grava
   `game_player_stats` direto (`jogos/[id]/actions.ts`, `lib/game-day.ts`) e
   usa as mesmas funções. Cada etapa no banco precisa ser testada nos dois
   clientes.

## Etapas

Cada etapa vira um PR que pode ir para produção sozinho. As etapas 1 a 3 não
tocam no banco.

### Etapa 0 — Versão mínima do app (opcional, recomendada)

- Tabela ou configuração `app_config` com `min_version` por plataforma, lida
  na abertura. Abaixo dela, aparece uma tela pedindo para atualizar.
- Sem isso, a Fase de limpeza fica presa até todo mundo atualizar sozinho.

### Etapa 1 — `SportRules` no app (só Dart, sem mudança visível)

Criar `lib/features/sports/domain/sport_rules.dart` com uma classe imutável
`SportRules` e a instância `footballRules`, preenchida com os valores de hoje:

```dart
class SportRules {
  final Sport sport;
  final List<Modality> modalities;
  final List<String> positions;          // hoje: lista de athlete.dart
  final PeriodRules periods;             // 2 tempos, rótulos, intervalo, acréscimo
  final int Function(Modality?) defaultPeriodMinutes;
  final int Function(Modality?) starters;
  final bool hasClock;                   // vôlei: false
  final bool allowsDraw;                 // amistoso e pontos corridos
  final KnockoutTiebreak knockoutTiebreak; // penalties | overtime | none
  final ScoreUnit scoreUnit;             // 'gol'/'gols', 'ponto'/'pontos'
  final List<StatDef> stats;             // gols, assistências, amarelo, vermelho
  final List<RankingDef> rankings;       // Artilharia (gols), Garçons (assistências)
  final StandingsRules standings;        // 3/1/0, ordem de desempate
  final bool supportsFieldLineup;        // escalação no campo (Premium)
}

SportRules rulesFor(Sport sport) => switch (sport) {
  Sport.football => footballRules,
  _ => throw UnsupportedError('Fase 2'),
};
```

- `Modality` ganha o campo `sport` (todas `Sport.football` por enquanto).
- `Team` ganha `SportRules get rules => rulesFor(sport)`. `Game` e
  `Championship` derivam o esporte da modalidade (`modality.sport`), sem
  coluna nova.
- `StatDef`: `key` (`goals`, `assists`, `yellow_cards`, `red_card`), rótulo,
  tipo (`count` ou `flag`) e máximo (amarelo até 2). O **craque** não vai para
  a lista: ele vale para todo esporte e continua como campo próprio.
- **Testes** (`test/features/sports/football_rules_test.dart`): verificar que
  `footballRules` devolve exatamente os valores de hoje (minutos por
  modalidade, titulares por modalidade, posições e pontuação 3/1/0). Esses
  testes são a garantia de que nada mudou.

### Etapa 2 — Telas e regras leem o `SportRules` (só Dart)

Trocar os valores escritos no código pela leitura das regras do time ou do jogo:

| Arquivo | Muda para |
|---|---|
| `games/domain/match_clock.dart` | `defaultPeriodMinutes` e rótulos das fases vêm de `rules.periods` |
| `home/presentation/match_clock_panel.dart` | rótulos e botões ("Encerrar 1º tempo") vêm de `rules.periods` |
| `games/data/lineup_repository.dart`, `lineup_page.dart` | `rules.starters(modality)` |
| `games/presentation/tactical_lineup.dart` | só aparece se `rules.supportsFieldLineup` |
| `athletes/presentation/athlete_form_page.dart`, `profile/presentation/athlete_data_page.dart` | `rules.positions`; pé dominante só se o esporte usa |
| `games/presentation/game_sheet_page.dart` | campos da súmula montados a partir de `rules.stats` |
| `athletes/presentation/athlete_profile_page.dart`, `profile/presentation/my_numbers_section.dart` | números a partir de `rules.stats` |
| `championships/presentation/championship_page.dart` | abas de ranking a partir de `rules.rankings`; pênaltis só se `knockoutTiebreak == penalties` |
| `championships/domain/championship_rules.dart` | `points` e a ordem de desempate vêm de `rules.standings` |
| `teams/domain/team_stats.dart`, `team_stats_widgets.dart` | "E" (empate) só se `allowsDraw` |
| `games/presentation/contest_score.dart`, `share_result.dart`, textos "gol" | `rules.scoreUnit` |

Nesta etapa, `PlayerGameStats` e `AthleteTotals` ainda leem as colunas antigas.
Cada um ganha um `Map<String, int> values` montado a partir delas, que as
telas passam a usar. Assim a Etapa 4 só troca a origem do mapa.

**Testes:** os testes atuais (`championship_rules_test`, `formation_test`,
`match_clock_test`, `championship_page_test`, `home_page_test`, `teams_test`)
precisam passar sem alteração. Se algum precisar mudar, é sinal de que o
comportamento mudou.

### Etapa 3 — `SportRules` no web (só TypeScript)

- `sportleague-web/src/lib/sports/rules.ts`, espelho da Etapa 1, com os
  mesmos `key` das estatísticas. `src/lib/modalities.ts` passa a usar esse
  arquivo.
- Mesma troca da Etapa 2 em: `jogos/[id]/live-panel.tsx`, `lib/live-game.ts`,
  `jogos/[id]/sumula/sheet-editor.tsx`, `lib/championships.ts`,
  `lib/championship-stats.ts`, `components/championship-*.tsx`,
  `atletas/[id]/page.tsx`, `lib/profile.ts`, `lib/public-profile.ts`.
- As definições que o banco também precisa validar (chaves das estatísticas,
  máximo de cada uma) vêm da tabela `sport_stat_defs` da Etapa 4. Os dois
  clientes ganham um teste que compara a cópia local com o banco, para as três
  cópias não ficarem diferentes.

### Etapa 4 — Súmula genérica no banco (aditiva)

Migration `…_sport_stats.sql`:

1. Tabela `public.sport_stat_defs` (`sport`, `key`, `kind` `count`/`flag`,
   `max_value`, `sort`). Todos podem ler. Linhas do futebol: `goals`,
   `assists`, `yellow_cards` (máx. 2), `red_card` (flag).
2. `game_player_stats.stats jsonb not null default '{}'`, preenchida com as
   colunas atuais (`update … set stats = jsonb_build_object(...)`).
3. Gatilho `private.check_player_stats` valida as chaves e os máximos de
   `stats` pela `sport_stat_defs` do esporte do jogo (que vem da modalidade).
4. **Compatibilidade nos dois sentidos** (gatilho `sync_legacy_stats`): quem
   grava as colunas antigas (app antigo, web antigo) atualiza `stats`, e quem
   grava `stats` atualiza as colunas antigas. Fica assim até a Fase de limpeza.
5. Nova versão de `team_player_totals`, `my_player_totals`,
   `championship_player_totals`, `public_profile` e `public_championship`:
   devolvem **também** `stats` (soma por chave, via `jsonb_each`) e continuam
   devolvendo `goals`, `assists`, `yellow_cards`, `red_cards`. Partir da
   **última** definição de cada uma: `team_player_totals` e
   `team_profile_stats` foram redefinidas 4 vezes, `public_profile` e
   `public_championship` 2 vezes.
6. `add_player_goal()` ganha uma irmã genérica `add_player_stat(game, athlete,
   key, delta)`. A antiga passa a chamar a nova com `goals`/`assists`.

Depois, o app (Etapa 2) e o web (Etapa 3) passam a ler e gravar `stats`.

> **Como ficou** (`20261127010000_sport_stats.sql`): os itens 1 a 4 e o 6
> (`add_player_stat`, com `add_player_goal` sem mudança). Entrou também a
> tabela `sport_modalities` (modalidade → esporte), que a validação precisa
> para saber o esporte do jogo. O item 5 (as funções de totais devolverem
> `stats`) ficou para a Fase 2: como as colunas do futebol continuam iguais a
> `stats` nos dois sentidos, as funções seguem certas, e só precisam mudar
> quando houver estatísticas que não são colunas (vôlei). Testada no banco de
> produção dentro de um bloco desfeito no fim (não há Supabase local e o
> histórico de migrations do projeto só começa em 04/11, então um branch não
> teria o esquema todo).
>
> **Ordem de publicação:** primeiro a migration; depois o site e o app, que
> passam a gravar `stats` (antes da migration, a coluna não existe). O app e
> o site antigos continuam funcionando depois da migration.

Escolhi `jsonb` em vez de uma tabela com uma linha por estatística porque a
súmula continua sendo **uma linha por atleta**. A chave primária
`(game_id, athlete_id)`, o índice do craque, a RLS e o upsert de hoje não
mudam.

> Conferir antes com a `feature/live-scoresheet` ("Live plays"): se ela cria
> jogadas ao vivo, as jogadas podem virar a origem dos números, e `stats`
> passa a ser a soma delas.

### Etapa 5 — Esporte no time e na modalidade (banco, aditiva)

- Tabela `public.sport_modalities` (`modality`, `sport`) com as cinco de hoje
  em `football`.
- Gatilho em `teams`: toda modalidade do time precisa ser do `teams.sport`.
  Todos os times atuais passam, porque já são todos futebol.
- `team_profile_stats()` passa a devolver `draws` só quando o esporte permite
  empate. No futebol, continua igual.
- A escolha do esporte no cadastro do time continua **escondida** (só aparece
  quando houver mais de um esporte liberado). Pode ser uma linha em
  `plan_features` ou uma configuração, para liberar o vôlei sem publicar
  versão nova.

> **Como ficou** (`20261127020000_team_sport_modalities.sql`): a tabela
> `sport_modalities` já tinha entrado na Etapa 4. O gatilho `teams_check_sport`
> recusa modalidade de outro esporte (`modality_sport`) e também a troca do
> esporte de um time existente (`team_sport_locked`), já que os jogos, a
> súmula e os campeonatos dele são daquele esporte. `team_profile_stats` não
> mudou: o app e o site já escondem "Empates" pelas regras, e no futebol nada
> muda. A escolha do esporte fica no cadastro do time (app) só quando
> `supportedSports` tiver mais de um esporte; liberar o vôlei é mudar essa
> lista (no app e no site) numa versão nova, e não uma configuração, porque
> sem as regras do vôlei no código não há o que mostrar.

### O que fica para a Fase 2 (vôlei) e a Fase 3 (basquete)

- **Relógio:** o banco continua com `match_phase` (first, interval, second,
  finished). Generalizar para `period smallint` + situação (rolando,
  intervalo, encerrado) quando o basquete chegar. Na Fase 1, a generalização
  fica só no Dart (`PeriodRules`). O vôlei não usa relógio.
- **Placar por set** (tabela `game_sets`) e classificação do vôlei
  (3/2/1/0, saldo de sets e de pontos).
- **Desempate do mata-mata:** prorrogação no basquete e sets no vôlei. Por
  enquanto, `advance_knockout()` continua com os pênaltis.
- Modalidades, posições, estatísticas e estampas de banner de cada esporte
  (`banners/presentation/football_patterns.dart`, `src/lib/banners/patterns.ts`).
- Ícones e textos por esporte nas notificações.

### Fase de limpeza (depois que todos atualizarem)

- Remover as colunas antigas de `game_player_stats` e o gatilho
  `sync_legacy_stats`.
- Tirar os campos antigos (`goals`, `assists`…) da saída das funções.
- Depende da Etapa 0, ou de acompanhar as versões em uso nas lojas.

## Verificação de cada PR

- `flutter test` passando, sem mudar nenhum teste antigo (só adicionar).
- Testes do web passando.
- Roteiro manual com um time de futebol, no app e no web: marcar amistoso,
  relógio (iniciar, pausar, 2º tempo, acréscimo, encerrar), gol pelo placar
  ao vivo com assistência, súmula com cartões e craque, perfil do atleta,
  Meus números, Artilharia/Garçons do time, campeonato de pontos corridos e
  de mata-mata com pênaltis, perfil público e campeonato público, imagem
  compartilhada.
- Etapas 4 e 5: rodar as migrations num **branch do Supabase**, comparar as
  funções de totais antes e depois para os mesmos times (a saída antiga tem
  que ser idêntica) e testar a súmula gravada pelo app **na versão de hoje**
  (a da loja).

## Ordem e tamanho

| Etapa | Toca em | Tamanho |
|---|---|---|
| 0. Versão mínima | app + banco | pequeno |
| 1. `SportRules` (Dart) | app | pequeno |
| 2. Telas leem as regras | app | médio |
| 3. `SportRules` (web) | web | médio |
| 4. Súmula genérica | banco + app + web | grande |
| 5. Esporte na modalidade | banco + app | pequeno |

As etapas 1, 2 e 3 podem começar já: elas não dependem do banco nem das
branches abertas. A Etapa 4 espera o merge da `feature/live-scoresheet` e da
`feature/championship-plus`.
