import '../../teams/domain/team.dart';

/// Como o campeonato é disputado (escolhido por quem cria).
enum ChampionshipFormat {
  league(
    'league',
    'Pontos corridos',
    'Todos contra todos; campeão é quem soma mais pontos',
  ),
  leagueKnockout(
    'league_knockout',
    'Liga + mata-mata',
    'Todos contra todos e os primeiros colocados fazem o mata-mata',
  ),
  knockout(
    'knockout',
    'Mata-mata',
    'Jogos eliminatórios até a final; empate vai para os pênaltis',
  ),
  groups(
    'groups',
    'Grupos + mata-mata',
    'Fase de grupos e os melhores de cada grupo no mata-mata',
  );

  const ChampionshipFormat(this.key, this.label, this.description);

  /// Como fica no banco.
  final String key;
  final String label;
  final String description;

  /// Tem a fase de todos contra todos (classificação única).
  bool get hasLeague => this == league || this == leagueKnockout;

  static ChampionshipFormat fromKey(String value) =>
      values.firstWhere((format) => format.key == value);
}

/// Grupos + mata-mata: como completar o mata-mata quando os classificados
/// diretos não fecham 2, 4, 8, 16 ou 32 times.
enum KnockoutFill {
  /// Entram os melhores colocados da posição seguinte (ex.: melhores 3º).
  bestPlaced('best_placed'),

  /// Os melhores classificados folgam e passam direto para a fase seguinte.
  byes('byes');

  const KnockoutFill(this.key);

  final String key;

  static KnockoutFill? fromKey(String? key) =>
      values.where((fill) => fill.key == key).firstOrNull;
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
    this.teamCount,
    this.groupSize,
    this.knockoutFill,
    this.knockoutQualifiers,
    this.status = ChampionshipStatus.draft,
    this.publicEnabled = false,
    this.publicSlug,
    this.yellowLimit = 3,
    this.redGames = 1,
    this.signupEnabled = false,
    this.signupCode,
  });

  factory Championship.fromMap(Map<String, dynamic> map) => Championship(
    id: map['id'] as String,
    ownerId: map['owner_id'] as String,
    name: map['name'] as String,
    // Modalidade desconhecida (esporte de uma versão mais nova) só para não
    // quebrar; as listas já tiram essas linhas (isSupportedModalityRow).
    modality:
        Modality.tryFromName(map['modality'] as String?) ??
        Modality.values.first,
    format: ChampionshipFormat.fromKey(map['format'] as String),
    doubleRound: map['double_round'] as bool? ?? false,
    groupCount: map['group_count'] as int?,
    qualifiersPerGroup: map['qualifiers_per_group'] as int?,
    teamCount: map['team_count'] as int?,
    groupSize: map['group_size'] as int?,
    knockoutFill: KnockoutFill.fromKey(map['knockout_fill'] as String?),
    knockoutQualifiers: map['knockout_qualifiers'] as int?,
    status: ChampionshipStatus.fromName(map['status'] as String),
    publicEnabled: map['public_enabled'] as bool? ?? false,
    publicSlug: map['public_slug'] as String?,
    yellowLimit: map['yellow_limit'] as int? ?? 3,
    redGames: map['red_games'] as int? ?? 1,
    signupEnabled: map['signup_enabled'] as bool? ?? false,
    signupCode: map['signup_code'] as String?,
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

  /// Grupos + mata-mata: quantos times o campeonato tem, o máximo por grupo
  /// e como completar o mata-mata (nulo quando os classificados fecham).
  final int? teamCount;
  final int? groupSize;
  final KnockoutFill? knockoutFill;

  /// Liga + mata-mata: quantos primeiros colocados vão ao mata-mata.
  final int? knockoutQualifiers;
  final ChampionshipStatus status;

  /// Link público (site, `/c/<código>`) ligado e o código; nulo até ligar a
  /// primeira vez. Muda só pelo `setPublic` do repositório.
  final bool publicEnabled;
  final String? publicSlug;

  /// Suspensão automática: a cada [yellowLimit] amarelos, 1 jogo (0
  /// desliga); expulsão, [redGames] jogos (0 desliga).
  final int yellowLimit;
  final int redGames;

  /// Inscrição por link (site, `/inscricao/<código>`): ligada e o código.
  /// Muda só pelo `setSignup` do repositório.
  final bool signupEnabled;
  final String? signupCode;

  /// "3 amarelos = 1 jogo · vermelho = 1 jogo" (ou "sem suspensão").
  String get suspensionRule {
    final parts = [
      if (yellowLimit > 0) '$yellowLimit amarelos = 1 jogo',
      if (redGames > 0)
        'vermelho = $redGames ${redGames == 1 ? 'jogo' : 'jogos'}',
    ];
    return parts.isEmpty ? 'Sem suspensão automática' : parts.join(' · ');
  }

  /// "Pontos corridos · turno e returno", "Grupos + mata-mata · 2 grupos".
  String get summary => switch (format) {
    ChampionshipFormat.league =>
      '${format.label} · ${doubleRound ? 'turno e returno' : 'turno único'}',
    ChampionshipFormat.leagueKnockout =>
      '${format.label} · ${doubleRound ? 'turno e returno' : 'turno único'}, '
          '$knockoutQualifiers primeiros no mata-mata',
    ChampionshipFormat.knockout => format.label,
    ChampionshipFormat.groups =>
      '${format.label} · ${teamCount == null ? '' : '$teamCount times, '}'
          '$groupCount grupos, '
          '${qualifiersPerGroup == 1 ? 'passa 1' : 'passam $qualifiersPerGroup'} '
          'de cada'
          '${switch (knockoutFill) {
            KnockoutFill.bestPlaced => ' + melhores ${(qualifiersPerGroup ?? 0) + 1}º',
            KnockoutFill.byes => ' + folgas',
            null => '',
          }}',
  };

  Map<String, dynamic> toMap() => {
    'owner_id': ownerId,
    'name': name.trim(),
    'modality': modality.key,
    'format': format.key,
    'double_round': format != ChampionshipFormat.knockout && doubleRound,
    'group_count': format == ChampionshipFormat.groups ? groupCount : null,
    'qualifiers_per_group': format == ChampionshipFormat.groups
        ? qualifiersPerGroup
        : null,
    'team_count': format == ChampionshipFormat.groups ? teamCount : null,
    'group_size': format == ChampionshipFormat.groups ? groupSize : null,
    'knockout_fill': format == ChampionshipFormat.groups
        ? knockoutFill?.key
        : null,
    'knockout_qualifiers': format == ChampionshipFormat.leagueKnockout
        ? knockoutQualifiers
        : null,
    'status': status.name,
    'yellow_limit': yellowLimit,
    'red_games': redGames,
  };

  Championship copyWith({
    ChampionshipStatus? status,
    bool? publicEnabled,
    String? publicSlug,
    bool? signupEnabled,
    String? signupCode,
  }) => Championship(
    id: id,
    ownerId: ownerId,
    name: name,
    modality: modality,
    format: format,
    doubleRound: doubleRound,
    groupCount: groupCount,
    qualifiersPerGroup: qualifiersPerGroup,
    teamCount: teamCount,
    groupSize: groupSize,
    knockoutFill: knockoutFill,
    knockoutQualifiers: knockoutQualifiers,
    status: status ?? this.status,
    publicEnabled: publicEnabled ?? this.publicEnabled,
    publicSlug: publicSlug ?? this.publicSlug,
    yellowLimit: yellowLimit,
    redGames: redGames,
    signupEnabled: signupEnabled ?? this.signupEnabled,
    signupCode: signupCode ?? this.signupCode,
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
