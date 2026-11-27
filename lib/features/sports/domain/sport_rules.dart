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
enum StandingsTiebreaker { points, wins, scoreDifference, scoreFor }

/// Pontuação e desempate da classificação.
class StandingsRules {
  const StandingsRules({
    required this.win,
    required this.draw,
    required this.loss,
    required this.tiebreakers,
  });

  final int win;
  final int draw;
  final int loss;

  /// Depois deles, vale o nome do time.
  final List<StandingsTiebreaker> tiebreakers;

  int pointsFor({required int wins, required int draws, required int losses}) =>
      wins * win + draws * draw + losses * loss;
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

/// Esportes que já têm regras (os outros ainda não aparecem no app).
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

/// Regras do [sport]. Só o futebol existe por enquanto.
SportRules rulesFor(Sport sport) => switch (sport) {
  Sport.football => footballRules,
  Sport.volleyball || Sport.basketball => throw UnsupportedError(
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
