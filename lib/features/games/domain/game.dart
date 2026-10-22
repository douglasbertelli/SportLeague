import '../../teams/domain/team.dart';

/// Situação guardada no banco. "Realizado" é derivado: marcado com a data já
/// passada (ver [Game.stageAt]).
enum GameStatus {
  /// Contra time da plataforma, aguardando o adversário aceitar.
  pending,
  scheduled,
  canceled;

  static GameStatus fromName(String value) =>
      GameStatus.values.firstWhere((status) => status.name == value);
}

/// Abas da lista de jogos, na ordem em que aparecem.
enum GameStage {
  scheduled('Marcados'),
  pending('Pendentes'),
  canceled('Cancelados'),
  played('Realizados');

  const GameStage(this.label);

  final String label;
}

/// Amistoso marcado pelo time [teamId]. O adversário é um time da plataforma
/// ([opponentTeamId]) ou um time fictício do administrador
/// ([opponentGuestId]); [opponent] guarda o nome para exibir mesmo se o time
/// for excluído. Contra um time da plataforma, o jogo aparece para os dois
/// times; os campos ficam do ponto de vista de quem marcou. O placar é lançado
/// em outra tela.
class Game {
  const Game({
    this.id,
    required this.teamId,
    required this.opponent,
    required this.scheduledAt,
    this.hostTeamName,
    this.status = GameStatus.scheduled,
    this.canceledByTeamId,
    this.modality,
    this.opponentTeamId,
    this.opponentGuestId,
    this.location,
    this.teamScore,
    this.opponentScore,
  });

  factory Game.fromMap(Map<String, dynamic> map) => Game(
    id: map['id'] as String,
    teamId: map['team_id'] as String,
    hostTeamName: (map['host'] as Map<String, dynamic>?)?['name'] as String?,
    status: GameStatus.fromName(map['status'] as String? ?? 'scheduled'),
    canceledByTeamId: map['canceled_by_team_id'] as String?,
    opponent: map['opponent'] as String,
    scheduledAt: DateTime.parse(map['scheduled_at'] as String).toLocal(),
    modality: switch (map['modality']) {
      final String name => Modality.fromName(name),
      _ => null,
    },
    opponentTeamId: map['opponent_team_id'] as String?,
    opponentGuestId: map['opponent_guest_id'] as String?,
    location: map['location'] as String?,
    teamScore: map['team_score'] as int?,
    opponentScore: map['opponent_score'] as int?,
  );

  /// Nulo antes de o jogo ser salvo.
  final String? id;

  /// Time que marcou o jogo (o único que pode editá-lo).
  final String teamId;

  /// Nome do time que marcou, carregado junto com o jogo para o adversário
  /// exibir; não é salvo.
  final String? hostTeamName;

  /// Definida pelo banco ao marcar e nas respostas (aceitar, cancelar); não é
  /// enviada pelo formulário.
  final GameStatus status;

  /// Time que cancelou ou recusou; nulo se o adversário foi excluído.
  final String? canceledByTeamId;

  /// Nome do adversário.
  final String opponent;

  /// Data e hora no fuso do aparelho.
  final DateTime scheduledAt;

  /// Nulo em jogos marcados antes deste campo; o formulário exige ao salvar.
  final Modality? modality;
  final String? opponentTeamId;
  final String? opponentGuestId;
  final String? location;
  final int? teamScore;
  final int? opponentScore;

  bool get hasScore => teamScore != null && opponentScore != null;

  /// Aba em que o jogo aparece no momento [now].
  GameStage stageAt(DateTime now) => switch (status) {
    GameStatus.pending => GameStage.pending,
    GameStatus.canceled => GameStage.canceled,
    GameStatus.scheduled when scheduledAt.isBefore(now) => GameStage.played,
    GameStatus.scheduled => GameStage.scheduled,
  };

  /// Se o time [viewerTeamId] marcou o jogo (senão, é o adversário).
  bool isHostedBy(String viewerTeamId) => teamId == viewerTeamId;

  /// Se o time [viewerTeamId] cancelou ou recusou o jogo.
  bool wasCanceledBy(String viewerTeamId) => canceledByTeamId == viewerTeamId;

  /// Nome do outro time, do ponto de vista de [viewerTeamId].
  String opponentNameFor(String viewerTeamId) =>
      isHostedBy(viewerTeamId) ? opponent : hostTeamName ?? 'Time adversário';

  /// "Vitória 3 x 1", "Empate 2 x 2" ou "Derrota 0 x 1" do ponto de vista de
  /// [viewerTeamId]; nulo sem placar.
  String? resultLabelFor(String viewerTeamId) {
    if (!hasScore) return null;
    final (mine, theirs) = isHostedBy(viewerTeamId)
        ? (teamScore!, opponentScore!)
        : (opponentScore!, teamScore!);
    final result = switch (mine.compareTo(theirs)) {
      > 0 => 'Vitória',
      0 => 'Empate',
      _ => 'Derrota',
    };
    return '$result $mine x $theirs';
  }

  /// Campos editados no formulário (o placar fica de fora).
  Map<String, dynamic> toMap() {
    final location = this.location?.trim();
    return {
      'team_id': teamId,
      'opponent': opponent.trim(),
      'opponent_team_id': opponentTeamId,
      'opponent_guest_id': opponentGuestId,
      'modality': modality?.name,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'location': location == null || location.isEmpty ? null : location,
    };
  }
}
