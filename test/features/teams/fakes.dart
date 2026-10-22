import 'package:sport_league/core/media/picked_image.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/availability/data/availability_repository.dart';
import 'package:sport_league/features/availability/domain/availability.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/games/data/opponent_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/domain/opponent.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';

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
  Future<void> cancel(String gameId) async => canceled.add(gameId);

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

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    for (final list in byTeam.values) {
      list.removeWhere((slot) => slot.id == id);
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
