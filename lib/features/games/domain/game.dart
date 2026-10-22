import '../../teams/domain/team.dart';
import '../../venues/domain/venue.dart';

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
    this.hostLogoUrl,
    this.hostCity,
    this.opponentLogoUrl,
    this.opponentCity,
    this.status = GameStatus.scheduled,
    this.canceledByTeamId,
    this.hostIsHome = true,
    this.modality,
    this.opponentTeamId,
    this.opponentGuestId,
    this.venueId,
    this.venue,
    this.location,
    this.teamScore,
    this.opponentScore,
  });

  factory Game.fromMap(Map<String, dynamic> map) {
    // Times carregados junto (select com host e opponent_team).
    final host = map['host'] as Map<String, dynamic>?;
    final opponentTeam = map['opponent_team'] as Map<String, dynamic>?;
    return Game(
      id: map['id'] as String,
      teamId: map['team_id'] as String,
      hostTeamName: host?['name'] as String?,
      hostLogoUrl: host?['logo_url'] as String?,
      hostCity: host?['city'] as String?,
      opponentLogoUrl: opponentTeam?['logo_url'] as String?,
      opponentCity: opponentTeam?['city'] as String?,
      status: GameStatus.fromName(map['status'] as String? ?? 'scheduled'),
      canceledByTeamId: map['canceled_by_team_id'] as String?,
      hostIsHome: map['host_is_home'] as bool? ?? true,
      opponent: map['opponent'] as String,
      scheduledAt: DateTime.parse(map['scheduled_at'] as String).toLocal(),
      modality: switch (map['modality']) {
        final String name => Modality.fromName(name),
        _ => null,
      },
      opponentTeamId: map['opponent_team_id'] as String?,
      opponentGuestId: map['opponent_guest_id'] as String?,
      venueId: map['venue_id'] as String?,
      venue: switch (map['venue']) {
        final Map<String, dynamic> venue => Venue.fromMap(venue),
        _ => null,
      },
      location: map['location'] as String?,
      teamScore: map['team_score'] as int?,
      opponentScore: map['opponent_score'] as int?,
    );
  }

  /// Nulo antes de o jogo ser salvo.
  final String? id;

  /// Time que marcou o jogo (o único que pode editá-lo).
  final String teamId;

  /// Nome, logo e cidade do time que marcou e do time adversário da
  /// plataforma, carregados junto com o jogo para o card; não são salvos.
  final String? hostTeamName;
  final String? hostLogoUrl;
  final String? hostCity;
  final String? opponentLogoUrl;
  final String? opponentCity;

  /// Definida pelo banco ao marcar e nas respostas (aceitar, cancelar); não é
  /// enviada pelo formulário.
  final GameStatus status;

  /// Time que cancelou ou recusou; nulo se o adversário foi excluído.
  final String? canceledByTeamId;

  /// Se o time que marcou joga como mandante; o adversário fica com o lado
  /// oposto.
  final bool hostIsHome;

  /// Nome do adversário.
  final String opponent;

  /// Data e hora no fuso do aparelho.
  final DateTime scheduledAt;

  /// Nulo em jogos marcados antes deste campo; o formulário exige ao salvar.
  final Modality? modality;
  final String? opponentTeamId;
  final String? opponentGuestId;

  /// Local da partida. Jogos antigos têm só o texto em [location].
  final String? venueId;

  /// Local carregado junto com o jogo (select com venue); não é salvo.
  final Venue? venue;
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

  /// Se o time [viewerTeamId] joga como mandante.
  bool isHomeFor(String viewerTeamId) =>
      isHostedBy(viewerTeamId) ? hostIsHome : !hostIsHome;

  /// Se o time [viewerTeamId] cancelou ou recusou o jogo.
  bool wasCanceledBy(String viewerTeamId) => canceledByTeamId == viewerTeamId;

  /// Nome do outro time, do ponto de vista de [viewerTeamId].
  String opponentNameFor(String viewerTeamId) =>
      isHostedBy(viewerTeamId) ? opponent : hostTeamName ?? 'Time adversário';

  /// Logo do outro time, do ponto de vista de [viewerTeamId] (nulo para time
  /// fictício ou sem logo).
  String? opponentLogoFor(String viewerTeamId) =>
      isHostedBy(viewerTeamId) ? opponentLogoUrl : hostLogoUrl;

  /// Cidade do outro time, do ponto de vista de [viewerTeamId].
  String? opponentCityFor(String viewerTeamId) =>
      isHostedBy(viewerTeamId) ? opponentCity : hostCity;

  /// Placar "mine × theirs" do ponto de vista de [viewerTeamId]; nulo sem
  /// placar.
  (int, int)? scoreFor(String viewerTeamId) {
    if (!hasScore) return null;
    return isHostedBy(viewerTeamId)
        ? (teamScore!, opponentScore!)
        : (opponentScore!, teamScore!);
  }

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
      'host_is_home': hostIsHome,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      'venue_id': venueId,
      'location': location == null || location.isEmpty ? null : location,
    };
  }
}
