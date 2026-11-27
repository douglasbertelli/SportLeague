import '../../games/domain/player_stats.dart';

/// Estatísticas do campeonato (função championship_stats): atletas, times,
/// suspensos e seleção da rodada.
class ChampionshipStats {
  const ChampionshipStats({
    this.players = const [],
    this.teams = const [],
    this.suspended = const [],
    this.rounds = const [],
    this.yellowLimit = 3,
    this.redGames = 1,
  });

  factory ChampionshipStats.fromMap(Map<String, dynamic> map) =>
      ChampionshipStats(
        players: [
          for (final row in map['players'] as List<dynamic>? ?? const [])
            StatsPlayer.fromMap(row as Map<String, dynamic>),
        ],
        teams: [
          for (final row in map['teams'] as List<dynamic>? ?? const [])
            StatsTeam.fromMap(row as Map<String, dynamic>),
        ],
        suspended: [
          for (final row in map['suspended'] as List<dynamic>? ?? const [])
            SuspendedPlayer.fromMap(row as Map<String, dynamic>),
        ],
        rounds: [
          for (final row in map['rounds'] as List<dynamic>? ?? const [])
            RoundSelection.fromMap(row as Map<String, dynamic>),
        ],
        yellowLimit: (map['yellow_limit'] as num?)?.toInt() ?? 3,
        redGames: (map['red_games'] as num?)?.toInt() ?? 1,
      );

  final List<StatsPlayer> players;
  final List<StatsTeam> teams;
  final List<SuspendedPlayer> suspended;
  final List<RoundSelection> rounds;
  final int yellowLimit;
  final int redGames;

  /// Rankings prontos (só quem tem o número, do maior para o menor).
  List<StatsPlayer> get scorers => _top((p) => p.goals);

  /// Ranking pela estatística [key] das regras do esporte.
  List<StatsPlayer> ranking(String key) => _top((p) => p.value(key));
  List<StatsPlayer> get assisters => _top((p) => p.assists);
  List<StatsPlayer> get carded => _top((p) => p.yellowCards + p.redCards * 3);

  List<StatsPlayer> _top(int Function(StatsPlayer) value) =>
      [
        for (final player in players)
          if (value(player) > 0) player,
      ]..sort((a, b) {
        final byValue = value(b).compareTo(value(a));
        return byValue != 0 ? byValue : a.name.compareTo(b.name);
      });

  /// Melhor ataque (mais gols), melhor defesa (menos gols sofridos, entre
  /// quem jogou) e fair play (menos pontos de cartão).
  List<StatsTeam> get byAttack => [
    for (final team in teams)
      if (team.played > 0) team,
  ]..sort((a, b) => b.goalsFor.compareTo(a.goalsFor));
  List<StatsTeam> get byDefense => [
    for (final team in teams)
      if (team.played > 0) team,
  ]..sort((a, b) => a.goalsAgainst.compareTo(b.goalsAgainst));
  List<StatsTeam> get byFairPlay => [
    for (final team in teams)
      if (team.played > 0) team,
  ]..sort((a, b) => a.fairPlay.compareTo(b.fairPlay));
}

class StatsPlayer {
  const StatsPlayer({
    required this.name,
    required this.teamName,
    this.logoUrl,
    this.goals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    this.bestPlayer = 0,
    this.games = 0,
    this.extra = const {},
  });

  factory StatsPlayer.fromMap(Map<String, dynamic> map) => StatsPlayer(
    name: map['name'] as String,
    teamName: map['team_name'] as String? ?? '',
    logoUrl: map['logo_url'] as String?,
    goals: (map['goals'] as num?)?.toInt() ?? 0,
    assists: (map['assists'] as num?)?.toInt() ?? 0,
    yellowCards: (map['yellow_cards'] as num?)?.toInt() ?? 0,
    redCards: (map['red_cards'] as num?)?.toInt() ?? 0,
    bestPlayer: (map['best_player'] as num?)?.toInt() ?? 0,
    games: (map['games'] as num?)?.toInt() ?? 0,
    // As estatísticas que não são colunas do futebol (vôlei).
    extra: extraStats(map['stats'] as Map<String, dynamic>?),
  );

  final String name;
  final String teamName;
  final String? logoUrl;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int bestPlayer;
  final int games;

  /// Totais das estatísticas que não são colunas do futebol (vôlei).
  final Map<String, int> extra;

  /// Total da estatística [key] das regras do esporte.
  int value(String key) => switch (key) {
    'goals' => goals,
    'assists' => assists,
    'yellow_cards' => yellowCards,
    'red_card' => redCards,
    _ => extra[key] ?? 0,
  };
}

class StatsTeam {
  const StatsTeam({
    required this.name,
    this.logoUrl,
    this.played = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.yellowCards = 0,
    this.redCards = 0,
  });

  factory StatsTeam.fromMap(Map<String, dynamic> map) => StatsTeam(
    name: map['name'] as String,
    logoUrl: map['logo_url'] as String?,
    played: (map['played'] as num?)?.toInt() ?? 0,
    goalsFor: (map['goals_for'] as num?)?.toInt() ?? 0,
    goalsAgainst: (map['goals_against'] as num?)?.toInt() ?? 0,
    yellowCards: (map['yellow_cards'] as num?)?.toInt() ?? 0,
    redCards: (map['red_cards'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final String? logoUrl;
  final int played;
  final int goalsFor;
  final int goalsAgainst;
  final int yellowCards;
  final int redCards;

  int get goalDifference => goalsFor - goalsAgainst;

  /// Pontos de disciplina: amarelo 1, vermelho 3 (menos é melhor).
  int get fairPlay => yellowCards + redCards * 3;
}

class SuspendedPlayer {
  const SuspendedPlayer({
    required this.name,
    required this.teamName,
    this.reason,
  });

  factory SuspendedPlayer.fromMap(Map<String, dynamic> map) => SuspendedPlayer(
    name: map['name'] as String,
    teamName: map['team_name'] as String? ?? '',
    reason: map['reason'] as String?,
  );

  final String name;
  final String teamName;
  final String? reason;
}

/// Seleção de uma rodada: o craque de cada jogo (cada time escolhe o seu) e,
/// primeiro, o craque da rodada.
class RoundSelection {
  const RoundSelection({
    required this.stage,
    required this.round,
    this.players = const [],
  });

  factory RoundSelection.fromMap(Map<String, dynamic> map) => RoundSelection(
    stage: map['stage'] as String,
    round: (map['round'] as num).toInt(),
    players: [
      for (final row in map['players'] as List<dynamic>? ?? const [])
        RoundPlayer.fromMap(row as Map<String, dynamic>),
    ],
  );

  final String stage;
  final int round;
  final List<RoundPlayer> players;
}

class RoundPlayer {
  const RoundPlayer({
    required this.name,
    required this.teamName,
    this.logoUrl,
    this.goals = 0,
    this.assists = 0,
    this.top = false,
  });

  factory RoundPlayer.fromMap(Map<String, dynamic> map) => RoundPlayer(
    name: map['name'] as String,
    teamName: map['team_name'] as String? ?? '',
    logoUrl: map['logo_url'] as String?,
    goals: (map['goals'] as num?)?.toInt() ?? 0,
    assists: (map['assists'] as num?)?.toInt() ?? 0,
    top: map['top'] as bool? ?? false,
  );

  final String name;
  final String teamName;
  final String? logoUrl;
  final int goals;
  final int assists;

  /// O craque da rodada.
  final bool top;
}

enum RequestStatus { pending, accepted, declined }

/// Pedido de inscrição pelo link: time da plataforma ou sem conta (com
/// responsável e elenco).
class ChampionshipRequest {
  const ChampionshipRequest({
    required this.id,
    required this.name,
    required this.createdAt,
    this.teamId,
    this.logoUrl,
    this.contactName,
    this.players = const [],
    this.status = RequestStatus.pending,
  });

  factory ChampionshipRequest.fromMap(Map<String, dynamic> map) =>
      ChampionshipRequest(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        teamId: map['team_id'] as String?,
        logoUrl: map['logo_url'] as String?,
        contactName: map['contact_name'] as String?,
        players: [
          for (final player in map['players'] as List<dynamic>? ?? const [])
            switch (player) {
              {'name': final String name, 'number': final int number} =>
                '$number · $name',
              {'name': final String name} => name,
              _ => '?',
            },
        ],
        status: RequestStatus.values.byName(map['status'] as String),
      );

  final String id;
  final String name;
  final DateTime createdAt;

  /// Time da plataforma; nulo para time sem conta.
  final String? teamId;
  final String? logoUrl;
  final String? contactName;

  /// Elenco do time sem conta ("10 · Zé").
  final List<String> players;
  final RequestStatus status;

  bool get hasAccount => teamId != null;
}
