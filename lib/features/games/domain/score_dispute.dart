/// Situação da contestação.
enum DisputeStatus {
  open,
  accepted,
  rejected;

  static DisputeStatus fromName(String value) =>
      DisputeStatus.values.firstWhere((status) => status.name == value);
}

/// Contestação do placar feita pelo adversário depois do jogo. O placar
/// proposto fica do ponto de vista de quem marcou o jogo, como em [Game].
class ScoreDispute {
  const ScoreDispute({
    this.id,
    required this.gameId,
    required this.teamId,
    required this.teamScore,
    required this.opponentScore,
    required this.message,
    this.status = DisputeStatus.open,
  });

  factory ScoreDispute.fromMap(Map<String, dynamic> map) => ScoreDispute(
    id: map['id'] as String,
    gameId: map['game_id'] as String,
    teamId: map['team_id'] as String,
    teamScore: map['team_score'] as int,
    opponentScore: map['opponent_score'] as int,
    message: map['message'] as String,
    status: DisputeStatus.fromName(map['status'] as String),
  );

  final String? id;
  final String gameId;

  /// Time que contestou (o adversário).
  final String teamId;
  final int teamScore;
  final int opponentScore;
  final String message;
  final DisputeStatus status;

  bool get isOpen => status == DisputeStatus.open;

  Map<String, dynamic> toMap() => {
    'game_id': gameId,
    'team_id': teamId,
    'team_score': teamScore,
    'opponent_score': opponentScore,
    'message': message.trim(),
  };
}
