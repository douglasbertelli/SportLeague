enum GameType {
  friendly('Amistoso'),
  championship('Campeonato');

  const GameType(this.label);

  final String label;

  static GameType fromName(String value) =>
      GameType.values.firstWhere((type) => type.name == value);
}

/// Jogo de um time. O adversário é só um nome; o placar é opcional e
/// preenchido depois do jogo (os dois lados juntos).
class Game {
  const Game({
    this.id,
    required this.teamId,
    required this.opponent,
    required this.scheduledAt,
    this.location,
    this.type = GameType.friendly,
    this.teamScore,
    this.opponentScore,
  });

  factory Game.fromMap(Map<String, dynamic> map) => Game(
    id: map['id'] as String,
    teamId: map['team_id'] as String,
    opponent: map['opponent'] as String,
    scheduledAt: DateTime.parse(map['scheduled_at'] as String).toLocal(),
    location: map['location'] as String?,
    type: GameType.fromName(map['type'] as String),
    teamScore: map['team_score'] as int?,
    opponentScore: map['opponent_score'] as int?,
  );

  /// Nulo antes de o jogo ser salvo.
  final String? id;
  final String teamId;
  final String opponent;

  /// Data e hora no fuso do aparelho.
  final DateTime scheduledAt;
  final String? location;
  final GameType type;
  final int? teamScore;
  final int? opponentScore;

  bool get hasScore => teamScore != null && opponentScore != null;

  /// "Vitória 3 x 1", "Empate 2 x 2" ou "Derrota 0 x 1"; nulo sem placar.
  String? get resultLabel {
    if (!hasScore) return null;
    final result = switch (teamScore!.compareTo(opponentScore!)) {
      > 0 => 'Vitória',
      0 => 'Empate',
      _ => 'Derrota',
    };
    return '$result $teamScore x $opponentScore';
  }

  Map<String, dynamic> toMap() {
    final location = this.location?.trim();
    return {
      'team_id': teamId,
      'opponent': opponent.trim(),
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'location': location == null || location.isEmpty ? null : location,
      'type': type.name,
      'team_score': teamScore,
      'opponent_score': opponentScore,
    };
  }
}
