import '../../teams/domain/team.dart';

/// Como o campeonato é disputado (escolhido por quem cria).
enum ChampionshipFormat {
  league(
    'Pontos corridos',
    'Todos contra todos; campeão é quem soma mais pontos',
  ),
  knockout(
    'Mata-mata',
    'Jogos eliminatórios até a final; empate vai para os pênaltis',
  ),
  groups(
    'Grupos + mata-mata',
    'Fase de grupos e os melhores de cada grupo no mata-mata',
  );

  const ChampionshipFormat(this.label, this.description);

  final String label;
  final String description;

  static ChampionshipFormat fromName(String value) =>
      values.firstWhere((format) => format.name == value);
}

enum ChampionshipStatus {
  draft('Inscrições'),
  running('Em andamento'),
  finished('Encerrado');

  const ChampionshipStatus(this.label);

  final String label;

  static ChampionshipStatus fromName(String value) =>
      values.firstWhere((status) => status.name == value);
}

class Championship {
  const Championship({
    this.id,
    required this.ownerId,
    required this.name,
    required this.modality,
    required this.format,
    this.doubleRound = false,
    this.groupCount,
    this.qualifiersPerGroup,
    this.status = ChampionshipStatus.draft,
  });

  factory Championship.fromMap(Map<String, dynamic> map) => Championship(
    id: map['id'] as String,
    ownerId: map['owner_id'] as String,
    name: map['name'] as String,
    modality: Modality.fromName(map['modality'] as String),
    format: ChampionshipFormat.fromName(map['format'] as String),
    doubleRound: map['double_round'] as bool? ?? false,
    groupCount: map['group_count'] as int?,
    qualifiersPerGroup: map['qualifiers_per_group'] as int?,
    status: ChampionshipStatus.fromName(map['status'] as String),
  );

  final String? id;
  final String ownerId;
  final String name;
  final Modality modality;
  final ChampionshipFormat format;

  /// Turno e returno (pontos corridos e grupos).
  final bool doubleRound;
  final int? groupCount;
  final int? qualifiersPerGroup;
  final ChampionshipStatus status;

  /// "Pontos corridos · turno e returno", "Grupos + mata-mata · 2 grupos".
  String get summary => switch (format) {
    ChampionshipFormat.league =>
      '${format.label} · ${doubleRound ? 'turno e returno' : 'turno único'}',
    ChampionshipFormat.knockout => format.label,
    ChampionshipFormat.groups =>
      '${format.label} · $groupCount grupos, '
          '${qualifiersPerGroup == 1 ? 'passa 1' : 'passam $qualifiersPerGroup'} '
          'de cada',
  };

  Map<String, dynamic> toMap() => {
    'owner_id': ownerId,
    'name': name.trim(),
    'modality': modality.name,
    'format': format.name,
    'double_round': format != ChampionshipFormat.knockout && doubleRound,
    'group_count': format == ChampionshipFormat.groups ? groupCount : null,
    'qualifiers_per_group': format == ChampionshipFormat.groups
        ? qualifiersPerGroup
        : null,
    'status': status.name,
  };

  Championship copyWith({ChampionshipStatus? status}) => Championship(
    id: id,
    ownerId: ownerId,
    name: name,
    modality: modality,
    format: format,
    doubleRound: doubleRound,
    groupCount: groupCount,
    qualifiersPerGroup: qualifiersPerGroup,
    status: status ?? this.status,
  );
}

enum EntryStatus {
  invited('Convidado'),
  accepted('Confirmado'),
  declined('Recusou');

  const EntryStatus(this.label);

  final String label;

  static EntryStatus fromName(String value) =>
      values.firstWhere((status) => status.name == value);
}

/// Time inscrito: da plataforma ([teamId]) ou fictício ([guestTeamId]).
class ChampionshipTeam {
  const ChampionshipTeam({
    required this.id,
    required this.championshipId,
    this.teamId,
    this.guestTeamId,
    required this.name,
    this.status = EntryStatus.accepted,
    this.groupLabel,
    this.logoUrl,
    this.ownerId,
  });

  factory ChampionshipTeam.fromMap(Map<String, dynamic> map) =>
      ChampionshipTeam(
        id: map['id'] as String,
        championshipId: map['championship_id'] as String,
        teamId: map['team_id'] as String?,
        guestTeamId: map['guest_team_id'] as String?,
        name: map['name'] as String,
        status: EntryStatus.fromName(map['status'] as String),
        groupLabel: map['group_label'] as String?,
        // Da plataforma, o logo do time; do fictício, a cópia na inscrição.
        logoUrl:
            (map['team'] as Map<String, dynamic>?)?['logo_url'] as String? ??
            map['logo_url'] as String?,
        ownerId: (map['team'] as Map<String, dynamic>?)?['owner_id'] as String?,
      );

  final String id;
  final String championshipId;
  final String? teamId;
  final String? guestTeamId;
  final String name;
  final EntryStatus status;
  final String? groupLabel;
  final String? logoUrl;

  /// Dono do time da plataforma (quem responde o convite).
  final String? ownerId;

  bool get isGuest => guestTeamId != null;
}

/// Números de um atleta no campeonato (soma da súmula dos jogos).
class ChampionshipPlayerTotal {
  const ChampionshipPlayerTotal({
    required this.athleteId,
    required this.name,
    required this.teamName,
    this.logoUrl,
    this.goals = 0,
    this.assists = 0,
    this.games = 0,
    this.bestPlayer = 0,
  });

  factory ChampionshipPlayerTotal.fromMap(Map<String, dynamic> map) =>
      ChampionshipPlayerTotal(
        athleteId: map['athlete_id'] as String,
        name: map['name'] as String,
        teamName: map['team_name'] as String,
        logoUrl: map['logo_url'] as String?,
        goals: map['goals'] as int? ?? 0,
        assists: map['assists'] as int? ?? 0,
        games: map['games'] as int? ?? 0,
        bestPlayer: map['best_player'] as int? ?? 0,
      );

  final String athleteId;
  final String name;
  final String teamName;
  final String? logoUrl;
  final int goals;
  final int assists;
  final int games;

  /// Vezes em que foi o craque do jogo.
  final int bestPlayer;
}

enum MatchStage { league, group, knockout }

class ChampionshipMatch {
  const ChampionshipMatch({
    required this.id,
    required this.championshipId,
    required this.stage,
    required this.round,
    this.slot = 0,
    this.groupLabel,
    this.homeId,
    this.awayId,
    this.scheduledAt,
    this.venueId,
    this.venueName,
    this.homeScore,
    this.awayScore,
    this.homePenalties,
    this.awayPenalties,
  });

  factory ChampionshipMatch.fromMap(Map<String, dynamic> map) =>
      ChampionshipMatch(
        id: map['id'] as String,
        championshipId: map['championship_id'] as String,
        stage: MatchStage.values.byName(map['stage'] as String),
        round: map['round'] as int,
        slot: map['slot'] as int? ?? 0,
        groupLabel: map['group_label'] as String?,
        homeId: map['home_id'] as String?,
        awayId: map['away_id'] as String?,
        scheduledAt: switch (map['scheduled_at']) {
          final String at => DateTime.parse(at).toLocal(),
          _ => null,
        },
        venueId: map['venue_id'] as String?,
        venueName: (map['venue'] as Map<String, dynamic>?)?['name'] as String?,
        homeScore: map['home_score'] as int?,
        awayScore: map['away_score'] as int?,
        homePenalties: map['home_penalties'] as int?,
        awayPenalties: map['away_penalties'] as int?,
      );

  final String id;
  final String championshipId;
  final MatchStage stage;
  final int round;
  final int slot;
  final String? groupLabel;

  /// Nulos no mata-mata enquanto a fase anterior não acaba (a definir).
  final String? homeId;
  final String? awayId;
  final DateTime? scheduledAt;
  final String? venueId;
  final String? venueName;
  final int? homeScore;
  final int? awayScore;
  final int? homePenalties;
  final int? awayPenalties;

  bool get hasScore => homeScore != null && awayScore != null;
  bool get hasTeams => homeId != null && awayId != null;

  /// Vencedor (com os pênaltis no empate); nulo sem placar ou empatado.
  String? get winnerId {
    if (!hasScore) return null;
    if (homeScore! > awayScore!) return homeId;
    if (awayScore! > homeScore!) return awayId;
    final home = homePenalties;
    final away = awayPenalties;
    if (home == null || away == null || home == away) return null;
    return home > away ? homeId : awayId;
  }
}
