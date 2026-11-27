import '../../athletes/domain/athlete.dart';
import '../../championships/domain/championship.dart';
import '../../games/domain/game.dart';
import '../../games/domain/game_event.dart';
import '../../teams/domain/team.dart';

/// Regras de um esporte: tudo o que muda de um esporte para outro (tempos,
/// titulares, súmula, classificação…) fica aqui, e não espalhado pelas
/// telas. Por enquanto só existe o futebol ([footballRules]); ver
/// `docs/multiesporte-fase1.md`.
class SportRules {
  const SportRules({
    required this.sport,
    required this.positions,
    required this.periods,
    required this.periodMinutes,
    required this.fallbackPeriodMinutes,
    required this.starters,
    required this.fallbackStarters,
    required this.hasClock,
    required this.allowsDraw,
    required this.knockoutTiebreak,
    required this.scoreUnit,
    required this.scoringStatKey,
    required this.stats,
    required this.rankings,
    required this.standings,
    required this.eventKinds,
    required this.supportsFieldLineup,
    required this.usesDominantFoot,
    this.sets,
    this.positionsByModality = const {},
  });

  final Sport sport;

  /// Posições oferecidas no cadastro do atleta e nos dados do jogador.
  final List<String> positions;

  /// Como a partida é dividida (tempos, quartos…).
  final PeriodRules periods;

  /// Duração sugerida de cada período, em minutos, por modalidade.
  final Map<Modality, int> periodMinutes;

  /// Duração sugerida quando o jogo não tem modalidade.
  final int fallbackPeriodMinutes;

  /// Quantos titulares começam jogando, por modalidade.
  final Map<Modality, int> starters;

  /// Titulares quando o jogo não tem modalidade.
  final int fallbackStarters;

  /// Se a partida tem relógio (o vôlei, por exemplo, não tem: joga por sets).
  final bool hasClock;

  /// Se o jogo pode terminar empatado (amistoso e pontos corridos).
  final bool allowsDraw;

  /// Como o empate se resolve no mata-mata.
  final KnockoutTiebreak knockoutTiebreak;

  /// Como se chama o ponto do placar ("gol", "ponto"…).
  final ScoreUnit scoreUnit;

  /// A estatística que soma no placar (gols): ordem da súmula e artilheiros
  /// da imagem compartilhada e do banner.
  final String scoringStatKey;

  /// O que cada atleta lança na súmula, na ordem das telas. O craque do jogo
  /// vale para todo esporte e não entra aqui.
  final List<StatDef> stats;

  /// Rankings dos atletas (perfil do time e campeonato).
  final List<RankingDef> rankings;

  /// Pontuação e desempate da classificação.
  final StandingsRules standings;

  /// Lances da súmula ao vivo.
  final List<GameEventKind> eventKinds;

  /// Se tem a escalação desenhada no campo (Premium).
  final bool supportsFieldLineup;

  /// Se o perfil do jogador pede o pé dominante.
  final bool usesDominantFoot;

  /// Placar em sets (vôlei); nulo quando o placar é um número só (futebol).
  final SetRules? sets;

  /// Posições de uma modalidade, quando diferem das do esporte (na praia não
  /// há levantador nem líbero).
  final Map<Modality, List<String>> positionsByModality;

  /// Posições oferecidas para um atleta da [modality].
  List<String> positionsFor(Modality? modality) =>
      positionsByModality[modality] ?? positions;

  /// Modalidades do esporte, na ordem do enum.
  List<Modality> get modalities => Modality.of(sport);

  /// Duração sugerida de cada período na [modality].
  int periodMinutesFor(Modality? modality) =>
      periodMinutes[modality] ?? fallbackPeriodMinutes;

  /// Titulares na [modality].
  int startersFor(Modality? modality) => starters[modality] ?? fallbackStarters;

  /// A estatística da súmula com a [key] (nula se o esporte não tem).
  StatDef? stat(String key) {
    for (final stat in stats) {
      if (stat.key == key) return stat;
    }
    return null;
  }
}

/// Divisão da partida.
class PeriodRules {
  const PeriodRules({
    required this.names,
    required this.intervalName,
    required this.hasAddedTime,
  });

  /// Nome de cada período, em ordem ("1º tempo", "2º tempo").
  final List<String> names;

  /// Nome da pausa entre os períodos.
  final String intervalName;

  /// Se o período continua depois do tempo regulamentar (acréscimo).
  final bool hasAddedTime;

  int get count => names.length;
}

/// Desempate do mata-mata.
enum KnockoutTiebreak {
  /// Disputa de pênaltis (placar à parte).
  penalties,

  /// Prorrogação até alguém vencer.
  overtime,

  /// Não há empate (vôlei: sempre há um vencedor de sets).
  none,
}

/// Nome do ponto do placar, no singular e no plural.
class ScoreUnit {
  const ScoreUnit(this.singular, this.plural);

  final String singular;
  final String plural;

  /// "1 gol", "3 gols".
  String count(int value) => '$value ${value == 1 ? singular : plural}';

  /// "Gols", para rótulos.
  String get title =>
      plural.isEmpty ? plural : plural[0].toUpperCase() + plural.substring(1);
}

/// Tipo de estatística da súmula.
enum StatKind {
  /// Contagem (0, 1, 2…), até [StatDef.max] quando tem limite.
  count,

  /// Sim ou não (cartão vermelho).
  flag,
}

/// Destaque da estatística nos quadros de números.
enum StatEmphasis { none, primary, error }

/// Uma estatística da súmula (`game_player_stats`).
class StatDef {
  const StatDef({
    required this.key,
    required this.label,
    required this.shortLabel,
    required this.totalsLabel,
    required this.unit,
    this.totalsTooltip,
    this.kind = StatKind.count,
    this.max,
    this.emphasis = StatEmphasis.none,
  });

  /// Nome da coluna no banco (`goals`, `yellow_cards`…).
  final String key;

  /// "Assistências".
  final String label;

  /// "Assist.", no lançamento da súmula.
  final String shortLabel;

  /// Nome nos quadros de totais ("Vermelhos", somando os jogos).
  final String totalsLabel;

  /// Dica do quadro de totais quando o nome é abreviado.
  final String? totalsTooltip;

  /// "1 assistência", "2 assistências" no resumo da súmula; a flag mostra só
  /// o singular ("vermelho").
  final ScoreUnit unit;

  final StatKind kind;

  /// Máximo por jogo (nulo = sem limite; flag é sempre 1).
  final int? max;

  final StatEmphasis emphasis;

  /// Como aparece no resumo da súmula; vazio quando é zero.
  String describe(int value) => switch (kind) {
    _ when value <= 0 => '',
    StatKind.flag => unit.singular,
    StatKind.count => unit.count(value),
  };
}

/// Ranking de atletas por uma estatística ("Artilharia" pelos gols).
class RankingDef {
  const RankingDef({
    required this.title,
    required this.statKey,
    required this.unit,
    this.emptyMessage,
  });

  final String title;
  final String statKey;

  /// Depois do número: "5 gols", "3 assist.".
  final String unit;

  /// Mensagem quando ninguém tem a estatística; nula esconde o ranking.
  final String? emptyMessage;
}

/// Critério de desempate da classificação, em ordem.
enum StandingsTiebreaker {
  points,
  wins,

  /// Saldo do placar: gols no futebol, sets no vôlei.
  scoreDifference,

  /// Placar marcado: gols no futebol, sets no vôlei.
  scoreFor,

  /// Saldo de pontos dentro dos sets (vôlei).
  pointDifference,
}

/// Pontuação e desempate da classificação.
class StandingsRules {
  const StandingsRules({
    required this.win,
    required this.draw,
    required this.loss,
    int? closeWin,
    int? closeLoss,
    required this.tiebreakers,
  }) : closeWin = closeWin ?? win,
       closeLoss = closeLoss ?? loss;

  final int win;
  final int draw;
  final int loss;

  /// Vitória e derrota apertadas (vôlei: decididas no tie-break, 3x2 ou
  /// 2x1). Sem valor, valem como as outras.
  final int closeWin;
  final int closeLoss;

  /// Depois deles, vale o nome do time.
  final List<StandingsTiebreaker> tiebreakers;

  /// Pontos de [wins] vitórias (das quais [closeWins] apertadas), [draws]
  /// empates e [losses] derrotas (das quais [closeLosses] apertadas).
  int pointsFor({
    required int wins,
    required int draws,
    required int losses,
    int closeWins = 0,
    int closeLosses = 0,
  }) =>
      (wins - closeWins) * win +
      closeWins * closeWin +
      draws * draw +
      (losses - closeLosses) * loss +
      closeLosses * closeLoss;
}

/// Placar em sets (vôlei): melhor de 3 ou de 5, sets até [pointsPerSet]
/// (pela modalidade) e o último, o tie-break, até [tieBreakPoints], sempre
/// com [minLead] pontos de diferença.
class SetRules {
  const SetRules({
    required this.bestOfOptions,
    required this.defaultBestOf,
    required this.pointsPerSet,
    required this.tieBreakPoints,
    this.minLead = 2,
  });

  /// Melhor de quantos sets dá para escolher (3 ou 5).
  final List<int> bestOfOptions;

  /// Melhor de sugerido por modalidade.
  final Map<Modality, int> defaultBestOf;

  /// Pontos de cada set (menos o tie-break), por modalidade.
  final Map<Modality, int> pointsPerSet;

  final int tieBreakPoints;
  final int minLead;

  /// Sets para vencer a partida: 2 na melhor de 3, 3 na melhor de 5.
  int setsToWin(int bestOf) => bestOf ~/ 2 + 1;

  /// Pontos do set [number] (1, 2…): o último possível é o tie-break.
  int targetFor(Modality? modality, int number, int bestOf) =>
      number == bestOf ? tieBreakPoints : pointsPerSet[modality] ?? 25;

  /// Se o set [a] x [b] terminou valendo: alguém chegou ao [target] com
  /// [minLead] de diferença; passando do [target], só com a diferença
  /// exata (26x24, não 27x24).
  bool isFinishedSet(int a, int b, int target) {
    final high = a > b ? a : b;
    final lead = (a - b).abs();
    if (a < 0 || b < 0 || high < target || lead < minLead) return false;
    return high == target || lead == minLead;
  }

  /// Confere a partida em [sets] (placar de cada set, do time e do
  /// adversário, ou do mandante e do visitante) e devolve os sets vencidos
  /// de cada lado; nulo se não vale (set que não terminou, sets depois de
  /// alguém já ter vencido, ou partida sem vencedor).
  ({int a, int b})? matchResult(
    List<(int, int)> sets, {
    required Modality? modality,
    required int bestOf,
  }) {
    if (!bestOfOptions.contains(bestOf)) return null;
    final toWin = setsToWin(bestOf);
    var (wonA, wonB) = (0, 0);
    for (final (index, (a, b)) in sets.indexed) {
      if (wonA == toWin || wonB == toWin) return null;
      if (!isFinishedSet(a, b, targetFor(modality, index + 1, bestOf))) {
        return null;
      }
      if (a > b) {
        wonA++;
      } else {
        wonB++;
      }
    }
    if (wonA != toWin && wonB != toWin) return null;
    return (a: wonA, b: wonB);
  }

  /// Se o resultado foi apertado (decidido no tie-break: 3x2, 2x1).
  bool isClose(({int a, int b}) result, int bestOf) =>
      (result.a < result.b ? result.a : result.b) == setsToWin(bestOf) - 1;
}

/// Classificação do futebol: 3 por vitória, 1 por empate; desempate por
/// vitórias, saldo de gols e gols marcados.
const footballStandings = StandingsRules(
  win: 3,
  draw: 1,
  loss: 0,
  tiebreakers: [
    StandingsTiebreaker.points,
    StandingsTiebreaker.wins,
    StandingsTiebreaker.scoreDifference,
    StandingsTiebreaker.scoreFor,
  ],
);

/// Futebol, com as regras de hoje.
const footballRules = SportRules(
  sport: Sport.football,
  positions: footballPositions,
  periods: PeriodRules(
    names: ['1º tempo', '2º tempo'],
    intervalName: 'Intervalo',
    hasAddedTime: true,
  ),
  periodMinutes: {
    Modality.futsal: 20,
    Modality.society: 25,
    Modality.field: 45,
    Modality.beach: 15,
    Modality.challenge: 10,
  },
  fallbackPeriodMinutes: 10,
  starters: {
    Modality.futsal: 5,
    Modality.beach: 5,
    Modality.society: 7,
    Modality.field: 11,
    Modality.challenge: 5,
  },
  fallbackStarters: 5,
  hasClock: true,
  allowsDraw: true,
  knockoutTiebreak: KnockoutTiebreak.penalties,
  scoreUnit: ScoreUnit('gol', 'gols'),
  scoringStatKey: 'goals',
  stats: [
    StatDef(
      key: 'goals',
      label: 'Gols',
      shortLabel: 'Gols',
      totalsLabel: 'Gols',
      unit: ScoreUnit('gol', 'gols'),
      emphasis: StatEmphasis.primary,
    ),
    StatDef(
      key: 'assists',
      label: 'Assistências',
      shortLabel: 'Assist.',
      totalsLabel: 'Assist.',
      totalsTooltip: 'Assistências',
      unit: ScoreUnit('assistência', 'assistências'),
    ),
    StatDef(
      key: 'yellow_cards',
      label: 'Amarelos',
      shortLabel: 'Amarelos',
      totalsLabel: 'Amarelos',
      unit: ScoreUnit('amarelo', 'amarelos'),
      max: 2,
    ),
    StatDef(
      key: 'red_card',
      label: 'Vermelho',
      shortLabel: 'Vermelho',
      totalsLabel: 'Vermelhos',
      unit: ScoreUnit('vermelho', 'vermelhos'),
      kind: StatKind.flag,
      emphasis: StatEmphasis.error,
    ),
  ],
  rankings: [
    RankingDef(
      title: 'Artilharia',
      statKey: 'goals',
      unit: 'gols',
      emptyMessage: 'Nenhum gol lançado nas súmulas ainda.',
    ),
    RankingDef(title: 'Garçons', statKey: 'assists', unit: 'assist.'),
  ],
  standings: footballStandings,
  eventKinds: GameEventKind.values,
  supportsFieldLineup: true,
  usesDominantFoot: true,
);

/// Classificação do vôlei (padrão CBV/FIVB): vitória por 3x0/3x1 (ou 2x0)
/// vale 3; no tie-break (3x2, 2x1), 2 para quem vence e 1 para quem perde.
/// Desempate por vitórias, saldo de sets e saldo de pontos.
const volleyballStandings = StandingsRules(
  win: 3,
  draw: 0,
  loss: 0,
  closeWin: 2,
  closeLoss: 1,
  tiebreakers: [
    StandingsTiebreaker.points,
    StandingsTiebreaker.wins,
    StandingsTiebreaker.scoreDifference,
    StandingsTiebreaker.pointDifference,
  ],
);

/// Vôlei (Fase 2, docs/multiesporte-fase2-volei.md). Existe no código, mas só
/// aparece quando entrar em [supportedSports].
const volleyballRules = SportRules(
  sport: Sport.volleyball,
  positions: ['Levantador', 'Oposto', 'Ponteiro', 'Central', 'Líbero'],
  positionsByModality: {
    Modality.volleyballBeach: ['Bloqueador', 'Defensor'],
  },
  periods: PeriodRules(
    names: ['1º set', '2º set', '3º set', '4º set', '5º set'],
    intervalName: 'Intervalo',
    hasAddedTime: false,
  ),
  // Sem relógio: o placar ao vivo é por set.
  periodMinutes: {},
  fallbackPeriodMinutes: 0,
  starters: {Modality.volleyballIndoor: 6, Modality.volleyballBeach: 2},
  fallbackStarters: 6,
  hasClock: false,
  allowsDraw: false,
  knockoutTiebreak: KnockoutTiebreak.none,
  scoreUnit: ScoreUnit('set', 'sets'),
  scoringStatKey: 'points',
  stats: [
    StatDef(
      key: 'points',
      label: 'Pontos',
      shortLabel: 'Pontos',
      totalsLabel: 'Pontos',
      unit: ScoreUnit('ponto', 'pontos'),
      emphasis: StatEmphasis.primary,
    ),
    StatDef(
      key: 'aces',
      label: 'Aces',
      shortLabel: 'Aces',
      totalsLabel: 'Aces',
      unit: ScoreUnit('ace', 'aces'),
    ),
    StatDef(
      key: 'blocks',
      label: 'Bloqueios',
      shortLabel: 'Bloq.',
      totalsLabel: 'Bloq.',
      totalsTooltip: 'Bloqueios',
      unit: ScoreUnit('bloqueio', 'bloqueios'),
    ),
  ],
  rankings: [
    RankingDef(
      title: 'Pontuadores',
      statKey: 'points',
      unit: 'pts',
      emptyMessage: 'Nenhum ponto lançado nas súmulas ainda.',
    ),
    RankingDef(title: 'Aces', statKey: 'aces', unit: 'aces'),
    RankingDef(title: 'Bloqueios', statKey: 'blocks', unit: 'bloq.'),
  ],
  standings: volleyballStandings,
  eventKinds: [],
  supportsFieldLineup: false,
  usesDominantFoot: false,
  sets: SetRules(
    bestOfOptions: [3, 5],
    defaultBestOf: {Modality.volleyballIndoor: 5, Modality.volleyballBeach: 3},
    pointsPerSet: {Modality.volleyballIndoor: 25, Modality.volleyballBeach: 21},
    tieBreakPoints: 15,
  ),
);

/// Esportes liberados nesta versão (os outros ainda não aparecem no app).
/// Liberar o vôlei é a Etapa 7 da Fase 2.
const supportedSports = [Sport.football];

/// Modalidades dos esportes liberados, para as listas de escolha (campeonato,
/// time fictício). Sem os esportes que ainda não aparecem no app.
List<Modality> get availableModalities => [
  for (final sport in supportedSports) ...Modality.of(sport),
];

/// Se a linha do banco (time: coluna `sport`) é de um esporte liberado nesta
/// versão do app. Times de um esporte que o app não conhece, ou que ainda
/// não liberou, ficam de fora das listas (não há regras para mostrá-los).
bool isSupportedSportRow(Map<String, dynamic> row) =>
    supportedSports.contains(Sport.tryFromName(row['sport'] as String?));

/// Se a linha do banco (campeonato, time fictício: coluna `modality`) é de
/// uma modalidade de um esporte liberado nesta versão do app.
bool isSupportedModalityRow(Map<String, dynamic> row) =>
    switch (Modality.tryFromName(row['modality'] as String?)) {
      final modality? => supportedSports.contains(modality.sport),
      null => false,
    };

/// Erro ao abrir algo (um campeonato, por exemplo) de um esporte que esta
/// versão do app ainda não tem.
class UnsupportedSportException implements Exception {
  const UnsupportedSportException();

  @override
  String toString() =>
      'Isto é de um esporte que esta versão do app ainda não tem. '
      'Atualize o app na loja.';
}

/// Regras do [sport] (ter regras não é estar liberado: ver
/// [supportedSports]). O basquete ainda não tem.
SportRules rulesFor(Sport sport) => switch (sport) {
  Sport.football => footballRules,
  Sport.volleyball => volleyballRules,
  Sport.basketball => throw UnsupportedError(
    '${sport.label} ainda não tem regras',
  ),
};

/// Regras do esporte da [modality]; sem modalidade, o futebol.
SportRules rulesForModality(Modality? modality) =>
    rulesFor(modality?.sport ?? Sport.football);

extension TeamSportRules on Team {
  SportRules get rules => rulesFor(sport);
}

extension GameSportRules on Game {
  /// O esporte vem da modalidade (amistosos só entre a mesma modalidade).
  Sport get sport => modality?.sport ?? Sport.football;

  SportRules get rules => rulesFor(sport);
}

extension ChampionshipSportRules on Championship {
  Sport get sport => modality.sport;

  SportRules get rules => rulesFor(sport);
}
