/// Linha da súmula: o que um atleta fez num jogo. Estar na súmula é ter
/// jogado a partida.
class PlayerGameStats {
  const PlayerGameStats({
    required this.gameId,
    required this.teamId,
    required this.athleteId,
    this.athleteName,
    this.jerseyNumber,
    this.goals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCard = false,
    this.bestPlayer = false,
  });

  factory PlayerGameStats.fromMap(Map<String, dynamic> map) {
    // Atleta carregado junto (select com athlete).
    final athlete = map['athlete'] as Map<String, dynamic>?;
    // A súmula genérica (`stats`, chave = estatística do esporte) vale; sem
    // ela (banco antes da migration sport_stats), as colunas do futebol.
    final stats = map['stats'] as Map<String, dynamic>?;
    int read(String key) =>
        (stats?[key] as num?)?.toInt() ??
        switch (map[key]) {
          final bool flag => flag ? 1 : 0,
          final num value => value.toInt(),
          _ => 0,
        };
    return PlayerGameStats(
      gameId: map['game_id'] as String,
      teamId: map['team_id'] as String,
      athleteId: map['athlete_id'] as String,
      // Do jogador vinculado, o apelido (ou o nome do perfil); do atleta sem
      // conta, o nome cadastrado no time.
      athleteName: switch (athlete?['profile']) {
        {'nickname': final String nickname} => nickname,
        {'full_name': final String fullName} => fullName,
        _ => athlete?['name'] as String?,
      },
      jerseyNumber: athlete?['jersey_number'] as int?,
      goals: read('goals'),
      assists: read('assists'),
      yellowCards: read('yellow_cards'),
      redCard: read('red_card') > 0,
      bestPlayer: map['best_player'] as bool? ?? false,
    );
  }

  final String gameId;
  final String teamId;
  final String athleteId;

  /// Nome e número do atleta, para mostrar a súmula; não são salvos.
  final String? athleteName;
  final int? jerseyNumber;

  final int goals;
  final int assists;

  /// 0, 1 ou 2.
  final int yellowCards;
  final bool redCard;

  /// Craque do jogo (um por time).
  final bool bestPlayer;

  PlayerGameStats copyWith({
    int? goals,
    int? assists,
    int? yellowCards,
    bool? redCard,
    bool? bestPlayer,
  }) => PlayerGameStats(
    gameId: gameId,
    teamId: teamId,
    athleteId: athleteId,
    athleteName: athleteName,
    jerseyNumber: jerseyNumber,
    goals: goals ?? this.goals,
    assists: assists ?? this.assists,
    yellowCards: yellowCards ?? this.yellowCards,
    redCard: redCard ?? this.redCard,
    bestPlayer: bestPlayer ?? this.bestPlayer,
  );

  /// Valor da estatística [key] das regras do esporte (flag: 0 ou 1).
  int value(String key) => switch (key) {
    'goals' => goals,
    'assists' => assists,
    'yellow_cards' => yellowCards,
    'red_card' => redCard ? 1 : 0,
    _ => 0,
  };

  /// Cópia com a estatística [key] valendo [value].
  PlayerGameStats withValue(String key, int value) => switch (key) {
    'goals' => copyWith(goals: value),
    'assists' => copyWith(assists: value),
    'yellow_cards' => copyWith(yellowCards: value),
    'red_card' => copyWith(redCard: value > 0),
    _ => this,
  };

  /// Linha para gravar: as estatísticas vão em `stats` (o banco mantém as
  /// colunas do futebol iguais a ela).
  Map<String, dynamic> toMap() => {
    'game_id': gameId,
    'team_id': teamId,
    'athlete_id': athleteId,
    'stats': {for (final key in _keys) key: value(key)},
    'best_player': bestPlayer,
  };

  /// Chaves de `stats` que esta linha conhece (as do futebol, por enquanto).
  static const _keys = ['goals', 'assists', 'yellow_cards', 'red_card'];
}

/// "Fulano (2)", "Ciclano": quem tem a estatística [key] (gols, no futebol),
/// de quem fez mais para quem fez menos.
List<String> scorerNames(Iterable<PlayerGameStats> stats, String key) {
  final scorers = stats.where((s) => s.value(key) > 0).toList()
    ..sort((a, b) => b.value(key).compareTo(a.value(key)));
  return [
    for (final s in scorers)
      '${s.athleteName ?? 'Atleta'}'
          '${s.value(key) > 1 ? ' (${s.value(key)})' : ''}',
  ];
}

/// Totais de um atleta em todos os jogos (perfil do atleta e artilharia).
class AthleteTotals {
  const AthleteTotals({
    required this.athleteId,
    required this.name,
    this.jerseyNumber,
    this.position,
    this.games = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    this.bestPlayer = 0,
  });

  factory AthleteTotals.fromMap(Map<String, dynamic> map) => AthleteTotals(
    athleteId: map['athlete_id'] as String,
    name: map['name'] as String,
    jerseyNumber: map['jersey_number'] as int?,
    position: map['position'] as String?,
    games: map['games'] as int? ?? 0,
    goals: map['goals'] as int? ?? 0,
    assists: map['assists'] as int? ?? 0,
    yellowCards: map['yellow_cards'] as int? ?? 0,
    redCards: map['red_cards'] as int? ?? 0,
    bestPlayer: map['best_player'] as int? ?? 0,
  );

  final String athleteId;
  final String name;
  final int? jerseyNumber;
  final String? position;
  final int games;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;

  /// Vezes em que foi o craque do jogo.
  final int bestPlayer;

  /// Total da estatística [key] das regras do esporte (a flag soma os jogos).
  int value(String key) => switch (key) {
    'goals' => goals,
    'assists' => assists,
    'yellow_cards' => yellowCards,
    'red_card' => redCards,
    _ => 0,
  };
}

/// Totais do jogador logado num dos times em que é atleta (Meus números).
class MyTeamTotals {
  const MyTeamTotals({
    required this.teamId,
    required this.teamName,
    this.teamLogoUrl,
    required this.totals,
  });

  factory MyTeamTotals.fromMap(Map<String, dynamic> map) => MyTeamTotals(
    teamId: map['team_id'] as String,
    teamName: map['team_name'] as String,
    teamLogoUrl: map['team_logo_url'] as String?,
    totals: AthleteTotals.fromMap({...map, 'name': map['team_name']}),
  );

  final String teamId;
  final String teamName;
  final String? teamLogoUrl;
  final AthleteTotals totals;
}
