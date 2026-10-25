/// Jogo no perfil do time, do ponto de vista dele.
class ProfileGame {
  const ProfileGame({
    required this.scheduledAt,
    required this.opponent,
    required this.isHome,
    this.opponentLogoUrl,
    this.goalsFor,
    this.goalsAgainst,
  });

  factory ProfileGame.fromMap(Map<String, dynamic> map) => ProfileGame(
    scheduledAt: DateTime.parse(map['scheduled_at'] as String).toLocal(),
    opponent: map['opponent'] as String,
    opponentLogoUrl: map['opponent_logo_url'] as String?,
    isHome: map['is_home'] as bool? ?? true,
    goalsFor: map['goals_for'] as int?,
    goalsAgainst: map['goals_against'] as int?,
  );

  final DateTime scheduledAt;
  final String opponent;

  /// Nulo para time fictício ou sem logo (mostra o escudo).
  final String? opponentLogoUrl;
  final bool isHome;

  /// Nulos enquanto o placar não foi lançado.
  final int? goalsFor;
  final int? goalsAgainst;

  bool get hasScore => goalsFor != null && goalsAgainst != null;

  /// "V", "E" ou "D"; nulo sem placar.
  String? get outcome => switch ((goalsFor, goalsAgainst)) {
    (final mine?, final theirs?) when mine > theirs => 'V',
    (final mine?, final theirs?) when mine == theirs => 'E',
    (_?, _?) => 'D',
    _ => null,
  };
}

/// Números do perfil público de um time (vêm do banco, sem expor os jogos).
class TeamStats {
  const TeamStats({
    this.played = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.followers = 0,
    this.following = 0,
    this.recent = const [],
    this.upcoming = const [],
  });

  factory TeamStats.fromMap(Map<String, dynamic> map) {
    List<ProfileGame> games(String key) => [
      for (final game in map[key] as List? ?? const [])
        ProfileGame.fromMap(game as Map<String, dynamic>),
    ];
    return TeamStats(
      played: map['played'] as int? ?? 0,
      wins: map['wins'] as int? ?? 0,
      draws: map['draws'] as int? ?? 0,
      losses: map['losses'] as int? ?? 0,
      goalsFor: map['goals_for'] as int? ?? 0,
      goalsAgainst: map['goals_against'] as int? ?? 0,
      followers: map['followers'] as int? ?? 0,
      following: map['following'] as int? ?? 0,
      recent: games('recent'),
      upcoming: games('upcoming'),
    );
  }

  /// Amistosos já realizados (com ou sem placar).
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int followers;
  final int following;

  /// Últimos realizados (mais recente primeiro) e próximos marcados.
  final List<ProfileGame> recent;
  final List<ProfileGame> upcoming;

  int get goalDifference => goalsFor - goalsAgainst;

  /// Pontos ganhos sobre os disputados (vitória 3, empate 1), em %, só dos
  /// jogos com placar; nulo sem nenhum.
  int? get winRate {
    final decided = wins + draws + losses;
    if (decided == 0) return null;
    return ((wins * 3 + draws) * 100 / (decided * 3)).round();
  }
}
