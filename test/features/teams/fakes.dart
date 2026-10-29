import 'package:sport_league/core/media/picked_image.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/availability/data/availability_repository.dart';
import 'package:sport_league/features/availability/domain/availability.dart';
import 'package:sport_league/features/games/data/dispute_repository.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/games/data/lineup_repository.dart';
import 'package:sport_league/features/games/data/player_stats_repository.dart';
import 'package:sport_league/features/games/data/opponent_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/domain/match_clock.dart';
import 'package:sport_league/features/games/domain/player_stats.dart';
import 'package:sport_league/features/games/domain/score_dispute.dart';
import 'package:sport_league/features/games/domain/opponent.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/season.dart';
import 'package:sport_league/features/teams/domain/team.dart';
import 'package:sport_league/features/teams/domain/team_stats.dart';
import 'package:sport_league/features/venues/data/venue_repository.dart';
import 'package:sport_league/features/venues/domain/venue.dart';

const teamA = Team(
  id: 'team-a',
  ownerId: 'u1',
  name: 'Amigos FC',
  modalities: {Modality.society, Modality.field},
);
const teamB = Team(
  id: 'team-b',
  ownerId: 'u1',
  name: 'Bola Murcha',
  modalities: {Modality.society},
  city: 'Campinas',
  state: 'SP',
);

class FakeTeamRepository implements TeamRepository {
  FakeTeamRepository([List<Team> teams = const []]) : teams = [...teams];

  final List<Team> teams;
  final created = <Team>[];
  final updated = <Team>[];
  final uploadedLogos = <String, PickedImage>{};

  @override
  Future<List<Team>> fetchByOwner(String ownerId) async =>
      teams.where((team) => team.ownerId == ownerId).toList();

  /// Ids dos times em que cada perfil é técnico.
  final coachedBy = <String, Set<String>>{};

  @override
  Future<List<Team>> fetchCoached(String profileId) async => [
    for (final team in teams)
      if (coachedBy[profileId]?.contains(team.id) ?? false) team,
  ];

  /// Ids dos times em que cada perfil é atleta (jogador vinculado).
  final playedBy = <String, Set<String>>{};

  @override
  Future<List<Team>> fetchPlayed(String profileId) async => [
    for (final team in teams)
      if (playedBy[profileId]?.contains(team.id) ?? false) team,
  ];

  @override
  Future<Team> create(Team team) async {
    // Ida e volta pelo formato do banco, como o Supabase faria.
    final saved = Team.fromMap({
      ...team.toMap(),
      'id': 'team-${teams.length + 1}',
    });
    created.add(team);
    teams.add(saved);
    return saved;
  }

  @override
  Future<void> update(Team team) async {
    updated.add(team);
    teams[teams.indexWhere((t) => t.id == team.id)] = team;
  }

  @override
  Future<String> uploadLogo(Team team, PickedImage image) async {
    uploadedLogos[team.id!] = image;
    return 'https://storage.test/team-logos/${team.ownerId}/${team.id}';
  }

  final uploadedCovers = <String, PickedImage>{};
  final uploadedKits = <PickedImage>[];
  final removedImages = <String>[];

  @override
  Future<String> uploadCover(Team team, PickedImage image) async {
    uploadedCovers[team.id!] = image;
    return 'https://storage.test/team-logos/${team.ownerId}/${team.id}-cover';
  }

  @override
  Future<String> uploadKit(Team team, PickedImage image) async {
    uploadedKits.add(image);
    return 'https://storage.test/team-logos/${team.ownerId}/${team.id}-kit-'
        '${uploadedKits.length}';
  }

  @override
  Future<void> removeImages(List<String> urls) async =>
      removedImages.addAll(urls);

  @override
  Future<Team?> fetchById(String teamId) async =>
      teams.where((team) => team.id == teamId).firstOrNull;

  @override
  Future<List<Team>> search(String query) async => [
    for (final team in teams)
      if (team.name.toLowerCase().contains(query.trim().toLowerCase())) team,
  ];

  /// Números de cada time no perfil; seguidores e seguindo vêm de [follows].
  final statsByTeam = <String, TeamStats>{};

  /// Temporadas pedidas nas estatísticas.
  final statsSeasons = <Season?>[];

  /// Pares (quem segue, quem é seguido).
  final follows = <({String follower, String followed})>{};

  @override
  Future<TeamStats> stats(String teamId, {Season? season}) async {
    statsSeasons.add(season);
    final base = statsByTeam[teamId] ?? const TeamStats();
    return TeamStats(
      played: base.played,
      wins: base.wins,
      draws: base.draws,
      losses: base.losses,
      goalsFor: base.goalsFor,
      goalsAgainst: base.goalsAgainst,
      recent: base.recent,
      upcoming: base.upcoming,
      followers: follows.where((f) => f.followed == teamId).length,
      following: follows.where((f) => f.follower == teamId).length,
    );
  }

  @override
  Future<bool> isFollowing(String followerId, String followedId) async =>
      follows.contains((follower: followerId, followed: followedId));

  @override
  Future<void> follow(String followerId, String followedId) async =>
      follows.add((follower: followerId, followed: followedId));

  @override
  Future<void> unfollow(String followerId, String followedId) async =>
      follows.remove((follower: followerId, followed: followedId));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Atletas guardados por time, como no banco.
class FakeAthleteRepository implements AthleteRepository {
  FakeAthleteRepository(this.byTeam);

  final Map<String, List<Athlete>> byTeam;

  @override
  Future<List<Athlete>> fetchByTeam(String teamId) async =>
      byTeam[teamId] ?? const [];

  final created = <Athlete>[];
  final updated = <Athlete>[];
  final uploadedPhotos = <String, PickedImage>{};

  @override
  Future<Athlete> create(Athlete athlete) async {
    final saved = Athlete.fromMap({
      ...athlete.toMap(),
      'id': 'athlete-${created.length + 1}',
    });
    created.add(athlete);
    (byTeam[athlete.teamId] ??= []).add(saved);
    return saved;
  }

  @override
  Future<void> update(Athlete athlete) async => updated.add(athlete);

  @override
  Future<String> uploadPhoto({
    required String ownerId,
    required Athlete athlete,
    required PickedImage image,
  }) async {
    uploadedPhotos[athlete.id!] = image;
    return '$ownerId/${athlete.teamId}/${athlete.id}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Jogos guardados por time, como no banco.
class FakeGameRepository implements GameRepository {
  FakeGameRepository(this.byTeam);

  final Map<String, List<Game>> byTeam;
  final created = <Game>[];
  final updated = <Game>[];

  /// Os jogos que o time marcou e os em que ele é o adversário, como o banco.
  @override
  Future<List<Game>> fetchByTeam(String teamId) async => [
    for (final games in byTeam.values)
      for (final game in games)
        if (game.teamId == teamId || game.opponentTeamId == teamId) game,
  ];

  @override
  Future<void> create(Game game) async {
    created.add(game);
    (byTeam[game.teamId] ??= []).add(game);
  }

  @override
  Future<void> update(Game game) async => updated.add(game);

  final accepted = <String>[];
  final canceled = <String>[];

  @override
  Future<void> accept(String gameId) async => accepted.add(gameId);

  @override
  Future<void> cancel(String gameId, {String? reason}) async {
    canceled.add(gameId);
    cancelReasons[gameId] = reason;
  }

  /// Motivo enviado em cada cancelamento.
  final cancelReasons = <String, String?>{};

  final scores = <String, (int, int)>{};

  @override
  Future<void> setScore(
    String gameId, {
    required int teamScore,
    required int opponentScore,
  }) async => scores[gameId] = (teamScore, opponentScore);

  final clockActions = <(String, ClockAction, int?)>[];

  @override
  Future<void> clock(
    String gameId,
    ClockAction action, {
    int? periodMinutes,
  }) async => clockActions.add((gameId, action, periodMinutes));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pesquisa que filtra pela modalidade e pelo nome, como o banco.
class FakeOpponentRepository implements OpponentRepository {
  FakeOpponentRepository({this.registered = const [], this.guests = const []});

  final List<Team> registered;
  final List<GuestTeam> guests;
  final searches =
      <({String teamId, String ownerId, Modality modality, String query})>[];
  final createdGuests = <GuestTeam>[];

  @override
  Future<({List<Team> registered, List<GuestTeam> guests})> search({
    required String teamId,
    required String ownerId,
    required Modality modality,
    required String query,
  }) async {
    searches.add((
      teamId: teamId,
      ownerId: ownerId,
      modality: modality,
      query: query,
    ));
    bool matches(String name) =>
        name.toLowerCase().contains(query.trim().toLowerCase());
    return (
      registered: [
        for (final team in registered)
          if (team.id != teamId &&
              team.modalities.contains(modality) &&
              matches(team.name))
            team,
      ],
      guests: [
        for (final guest in guests)
          if (guest.ownerId == ownerId &&
              guest.modality == modality &&
              matches(guest.name))
            guest,
      ],
    );
  }

  @override
  Future<GuestTeam> createGuest(GuestTeam guest) async {
    createdGuests.add(guest);
    return GuestTeam(
      id: 'guest-${createdGuests.length}',
      ownerId: guest.ownerId,
      name: guest.name,
      modality: guest.modality,
    );
  }
}

const arena = Venue(
  id: 'venue-1',
  createdBy: 'u2',
  name: 'Arena Society Central',
  zipCode: '13010000',
  street: 'Rua das Flores',
  number: '120',
  neighborhood: 'Centro',
  city: 'Campinas',
  state: 'SP',
);

/// Locais compartilhados: a pesquisa filtra pelo nome e os parecidos são os
/// de mesmo nome (sem diferenciar maiúsculas) na mesma cidade.
class FakeVenueRepository implements VenueRepository {
  FakeVenueRepository([List<Venue> venues = const []]) : venues = [...venues];

  final List<Venue> venues;
  final created = <Venue>[];
  final similarChecks = <Venue>[];

  @override
  Future<List<Venue>> search(String query) async => [
    for (final venue in venues)
      if (venue.name.toLowerCase().contains(query.trim().toLowerCase())) venue,
  ];

  @override
  Future<List<Venue>> findSimilar(Venue venue) async {
    similarChecks.add(venue);
    return [
      for (final other in venues)
        if (other.city == venue.city &&
            other.name.toLowerCase().contains(venue.name.trim().toLowerCase()))
          other,
    ];
  }

  @override
  Future<Venue> create(Venue venue) async {
    created.add(venue);
    final saved = Venue.fromMap({
      ...venue.toMap(),
      'id': 'venue-${venues.length + 1}',
    });
    venues.add(saved);
    return saved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Horários cadastrados e livres por time, como o banco.
class FakeAvailabilityRepository implements AvailabilityRepository {
  FakeAvailabilityRepository({
    Map<String, List<Availability>> byTeam = const {},
    this.freeByTeam = const {},
  }) : byTeam = {
         for (final entry in byTeam.entries) entry.key: [...entry.value],
       };

  final Map<String, List<Availability>> byTeam;
  final Map<String, List<DateTime>> freeByTeam;
  final added = <Availability>[];
  final deleted = <String>[];
  final freeSlotRequests = <String>[];

  @override
  Future<List<Availability>> fetchByTeam(String teamId) async =>
      byTeam[teamId] ?? const [];

  @override
  Future<void> add(Availability availability) async {
    added.add(availability);
    (byTeam[availability.teamId] ??= []).add(availability);
  }

  final updated = <Availability>[];

  @override
  Future<void> update(Availability availability) async {
    updated.add(availability);
    for (final list in byTeam.values) {
      final index = list.indexWhere((slot) => slot.id == availability.id);
      if (index >= 0) list[index] = availability;
    }
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    for (final list in byTeam.values) {
      list.removeWhere((slot) => slot.id == id);
    }
  }

  final skipped = <({String availabilityId, DateTime date})>[];

  @override
  Future<void> skipDate(String availabilityId, DateTime date) async {
    skipped.add((availabilityId: availabilityId, date: date));
    for (final list in byTeam.values) {
      final index = list.indexWhere((slot) => slot.id == availabilityId);
      if (index < 0) continue;
      final slot = list[index];
      list[index] = Availability.weekly(
        id: slot.id,
        teamId: slot.teamId,
        weekday: slot.weekday!,
        startTime: slot.startTime!,
        startsOn: slot.startsOn,
        skippedDates: {...slot.skippedDates, date},
      );
    }
  }

  @override
  Future<List<DateTime>> freeSlots(
    String teamId, {
    required DateTime from,
    required DateTime to,
  }) async {
    freeSlotRequests.add(teamId);
    return freeByTeam[teamId] ?? const [];
  }
}

/// Contestações em memória; [hostByGame] diz quem marcou cada jogo.
class FakeDisputeRepository implements DisputeRepository {
  FakeDisputeRepository({
    List<ScoreDispute> disputes = const [],
    this.hostByGame = const {},
  }) : disputes = [...disputes];

  final List<ScoreDispute> disputes;
  final Map<String, String> hostByGame;
  final resolved = <(String, bool)>[];

  @override
  Future<List<ScoreDispute>> openForTeam(String teamId) async => [
    for (final dispute in disputes)
      if (dispute.isOpen &&
          (dispute.teamId == teamId || hostByGame[dispute.gameId] == teamId))
        dispute,
  ];

  @override
  Future<void> create(ScoreDispute dispute) async => disputes.add(
    ScoreDispute(
      id: 'd${disputes.length + 1}',
      gameId: dispute.gameId,
      teamId: dispute.teamId,
      teamScore: dispute.teamScore,
      opponentScore: dispute.opponentScore,
      message: dispute.message,
    ),
  );

  @override
  Future<void> resolve(String disputeId, {required bool accept}) async {
    resolved.add((disputeId, accept));
    disputes.removeWhere((dispute) => dispute.id == disputeId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Súmulas em memória.
class FakePlayerStatsRepository implements PlayerStatsRepository {
  FakePlayerStatsRepository({
    List<PlayerGameStats> stats = const [],
    this.totalsByTeam = const {},
    this.mine = const [],
  }) : stats = [...stats];

  final List<PlayerGameStats> stats;
  final Map<String, List<AthleteTotals>> totalsByTeam;

  /// Números do jogador logado, por time.
  final List<MyTeamTotals> mine;
  final goals = <({String scorer, String? assist})>[];

  @override
  Future<List<PlayerGameStats>> fetchGame(String gameId) async => [
    for (final row in stats)
      if (row.gameId == gameId) row,
  ];

  @override
  Future<void> saveTeamSheet({
    required String gameId,
    required String teamId,
    required List<PlayerGameStats> rows,
  }) async {
    stats
      ..removeWhere((row) => row.gameId == gameId && row.teamId == teamId)
      ..addAll(rows);
  }

  @override
  Future<void> addGoal({
    required String gameId,
    required String teamId,
    required String scorerId,
    String? assistId,
  }) async => goals.add((scorer: scorerId, assist: assistId));

  @override
  Future<List<AthleteTotals>> teamTotals(
    String teamId, {
    Season? season,
  }) async => totalsByTeam[teamId] ?? const [];

  @override
  Future<List<MyTeamTotals>> myTotals({Season? season}) async => mine;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Escalações em memória.
class FakeLineupRepository implements LineupRepository {
  FakeLineupRepository([List<(String, LineupEntry)> entries = const []])
    : entries = [...entries];

  /// (jogo, escalação).
  final List<(String, LineupEntry)> entries;

  @override
  Future<List<LineupEntry>> fetchGame(String gameId) async => [
    for (final (game, entry) in entries)
      if (game == gameId) entry,
  ];

  @override
  Future<void> saveTeam({
    required String gameId,
    required String teamId,
    required List<LineupEntry> entries,
  }) async {
    this.entries
      ..removeWhere((row) => row.$1 == gameId && row.$2.teamId == teamId)
      ..addAll([for (final entry in entries) (gameId, entry)]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
