import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';

const teamA = Team(id: 'team-a', ownerId: 'u1', name: 'Amigos FC');
const teamB = Team(
  id: 'team-b',
  ownerId: 'u1',
  name: 'Bola Murcha',
  city: 'Campinas',
  state: 'SP',
);

class FakeTeamRepository implements TeamRepository {
  FakeTeamRepository([List<Team> teams = const []]) : teams = [...teams];

  final List<Team> teams;
  final created = <Team>[];

  @override
  Future<List<Team>> fetchByOwner(String ownerId) async =>
      teams.where((team) => team.ownerId == ownerId).toList();

  @override
  Future<Team> create(Team team) async {
    final saved = Team(
      id: 'team-${teams.length + 1}',
      ownerId: team.ownerId,
      name: team.name,
      city: team.city,
      state: team.state,
      description: team.description,
    );
    created.add(team);
    teams.add(saved);
    return saved;
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

  @override
  Future<void> create(Athlete athlete) async =>
      (byTeam[athlete.teamId] ??= []).add(athlete);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Jogos guardados por time, como no banco.
class FakeGameRepository implements GameRepository {
  FakeGameRepository(this.byTeam);

  final Map<String, List<Game>> byTeam;
  final created = <Game>[];

  @override
  Future<List<Game>> fetchByTeam(String teamId) async =>
      byTeam[teamId] ?? const [];

  @override
  Future<void> create(Game game) async {
    created.add(game);
    (byTeam[game.teamId] ??= []).add(game);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
