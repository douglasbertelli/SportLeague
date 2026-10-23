import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/game.dart';

class GameRepository {
  GameRepository(this._client);

  final SupabaseClient _client;

  /// Jogos do time, do mais antigo para o mais recente: os que ele marcou e
  /// os amistosos em que foi escolhido como adversário. Traz o nome de quem
  /// marcou para o adversário exibir.
  Future<List<Game>> fetchByTeam(String teamId) async {
    final rows = await _client
        .from('games')
        .select(
          '*, host:teams!games_team_id_fkey(name, logo_url, city), '
          'opponent_team:teams!games_opponent_team_id_fkey(logo_url, city), '
          'venue:venues(*)',
        )
        .or('team_id.eq.$teamId,opponent_team_id.eq.$teamId')
        .order('scheduled_at');
    return rows.map(Game.fromMap).toList();
  }

  Future<void> create(Game game) => _client.from('games').insert(game.toMap());

  Future<void> update(Game game) =>
      _client.from('games').update(game.toMap()).eq('id', game.id!);

  Future<void> delete(String gameId) =>
      _client.from('games').delete().eq('id', gameId);

  /// Placar lançado por quem marcou, depois do jogo.
  Future<void> setScore(
    String gameId, {
    required int teamScore,
    required int opponentScore,
  }) => _client
      .from('games')
      .update({'team_score': teamScore, 'opponent_score': opponentScore})
      .eq('id', gameId);

  /// O adversário aceita o amistoso pendente.
  Future<void> accept(String gameId) =>
      _setStatus(gameId, GameStatus.scheduled);

  /// Cancela (ou recusa, se pendente). Vale para os dois times; o banco
  /// registra qual deles cancelou.
  Future<void> cancel(String gameId) => _setStatus(gameId, GameStatus.canceled);

  Future<void> _setStatus(String gameId, GameStatus status) =>
      _client.from('games').update({'status': status.name}).eq('id', gameId);
}

final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => GameRepository(ref.watch(supabaseClientProvider)),
);

/// Jogos de um time.
final teamGamesProvider = FutureProvider.family<List<Game>, String>(
  (ref, teamId) => ref.watch(gameRepositoryProvider).fetchByTeam(teamId),
);
