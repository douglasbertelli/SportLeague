import 'package:sport_league/features/games/data/presence_repository.dart';
import 'package:sport_league/features/games/domain/presence_answer.dart';

class FakePresenceRepository implements PresenceRepository {
  FakePresenceRepository({this.mine = const {}, this.team = const []});

  Map<String, PresenceAnswer?> mine;
  final List<PresenceEntry> team;
  final answers = <(String, String, PresenceAnswer)>[];
  final requests = <(String, String)>[];

  @override
  Future<void> answer(
    String gameId,
    String teamId,
    PresenceAnswer answer,
  ) async {
    answers.add((gameId, teamId, answer));
    mine = {...mine, gameId: answer};
  }

  @override
  Future<int> request(String gameId, String teamId) async {
    requests.add((gameId, teamId));
    return team.where((entry) => entry.answer == null).length;
  }

  @override
  Future<Map<String, PresenceAnswer?>> fetchMine(String userId) async => mine;

  @override
  Future<List<PresenceEntry>> fetchGame(String gameId, String teamId) async =>
      team;
}
