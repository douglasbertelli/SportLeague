/// Situação de um convite ou pedido para entrar num time.
enum InviteStatus {
  pending('Aguardando'),
  accepted('Aceito'),
  declined('Recusado'),
  canceled('Cancelado');

  const InviteStatus(this.label);

  final String label;

  static InviteStatus fromName(String value) =>
      InviteStatus.values.firstWhere((status) => status.name == value);
}

/// Conta de jogador na pesquisa para convidar.
class PlayerSummary {
  const PlayerSummary({required this.id, required this.name, this.avatarUrl});

  factory PlayerSummary.fromMap(Map<String, dynamic> map) => PlayerSummary(
    id: map['id'] as String,
    name: map['full_name'] as String,
    avatarUrl: map['avatar_url'] as String?,
  );

  final String id;
  final String name;
  final String? avatarUrl;
}

/// Convite do time ao jogador ([isRequest] falso) ou pedido do jogador para
/// entrar no time ([isRequest] verdadeiro). Entrar com o código fica
/// registrado como um pedido já aceito.
class TeamInvite {
  const TeamInvite({
    required this.id,
    required this.teamId,
    required this.profileId,
    required this.isRequest,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    this.playerName,
    this.playerAvatarUrl,
    this.teamName,
    this.teamLogoUrl,
  });

  factory TeamInvite.fromMap(Map<String, dynamic> map) {
    final player = map['player'] as Map<String, dynamic>?;
    final team = map['team'] as Map<String, dynamic>?;
    return TeamInvite(
      id: map['id'] as String,
      teamId: map['team_id'] as String,
      profileId: map['profile_id'] as String,
      isRequest: map['direction'] == 'request',
      status: InviteStatus.fromName(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      respondedAt: switch (map['responded_at']) {
        final String at => DateTime.parse(at).toLocal(),
        _ => null,
      },
      playerName: player?['full_name'] as String?,
      playerAvatarUrl: player?['avatar_url'] as String?,
      teamName: team?['name'] as String?,
      teamLogoUrl: team?['logo_url'] as String?,
    );
  }

  final String id;
  final String teamId;

  /// Jogador convidado ou que pediu para entrar.
  final String profileId;
  final bool isRequest;
  final InviteStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  /// Carregados junto (select com player e team); não são salvos.
  final String? playerName;
  final String? playerAvatarUrl;
  final String? teamName;
  final String? teamLogoUrl;

  bool get isPending => status == InviteStatus.pending;
}
