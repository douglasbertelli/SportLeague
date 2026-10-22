import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/game.dart';

class GameRepository {
  GameRepository(this._client);

  final SupabaseClient _client;

  /// Jogos do time, do mais antigo para o mais recente.
  Future<List<Game>> fetchByTeam(String teamId) async {
    final rows = await _client
        .from('games')
        .select()
        .eq('team_id', teamId)
        .order('scheduled_at');
    return rows.map(Game.fromMap).toList();
  }

  Future<void> create(Game game) => _client.from('games').insert(game.toMap());

  Future<void> update(Game game) =>
      _client.from('games').update(game.toMap()).eq('id', game.id!);

  Future<void> delete(String gameId) =>
      _client.from('games').delete().eq('id', gameId);
}

final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => GameRepository(ref.watch(supabaseClientProvider)),
);

/// Jogos de um time.
final teamGamesProvider = FutureProvider.family<List<Game>, String>(
  (ref, teamId) => ref.watch(gameRepositoryProvider).fetchByTeam(teamId),
);
