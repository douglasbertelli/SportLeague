import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../teams/domain/season.dart';
import '../domain/player_stats.dart';

class PlayerStatsRepository {
  PlayerStatsRepository(this._client);

  final SupabaseClient _client;

  /// Súmula do jogo (os dois times), com nome e número dos atletas.
  Future<List<PlayerGameStats>> fetchGame(String gameId) async {
    final rows = await _client
        .from('game_player_stats')
        .select('*, athlete:team_players(name, jersey_number)')
        .eq('game_id', gameId);
    return rows.map(PlayerGameStats.fromMap).toList();
  }

  /// Salva a súmula de um time: quem está em [rows] jogou; quem saiu da lista
  /// sai da súmula.
  Future<void> saveTeamSheet({
    required String gameId,
    required String teamId,
    required List<PlayerGameStats> rows,
  }) async {
    final keep = [for (final row in rows) row.athleteId];
    var remove = _client
        .from('game_player_stats')
        .delete()
        .eq('game_id', gameId)
        .eq('team_id', teamId);
    if (keep.isNotEmpty) {
      remove = remove.not('athlete_id', 'in', '(${keep.join(',')})');
    }
    await remove;
    if (rows.isEmpty) return;
    // O craque sai antes de entrar o novo (um por time).
    await _client
        .from('game_player_stats')
        .update({'best_player': false})
        .eq('game_id', gameId)
        .eq('team_id', teamId)
        .eq('best_player', true);
    await _client.from('game_player_stats').upsert([
      for (final row in rows) row.toMap(),
    ]);
  }

  /// Gol do placar ao vivo: soma o gol de [scorerId] e a assistência de
  /// [assistId].
  Future<void> addGoal({
    required String gameId,
    required String teamId,
    required String scorerId,
    String? assistId,
  }) => _client.rpc(
    'add_player_goal',
    params: {
      'p_game': gameId,
      'p_team': teamId,
      'p_scorer': scorerId,
      'p_assist': assistId,
    },
  );

  /// Totais de cada atleta do time; com [season], só os jogos da temporada.
  Future<List<AthleteTotals>> teamTotals(
    String teamId, {
    Season? season,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'team_player_totals',
      params: {
        'p_team': teamId,
        'p_from': season?.start.toUtc().toIso8601String(),
        'p_to': season?.end.toUtc().toIso8601String(),
      },
    );
    return [
      for (final row in rows)
        AthleteTotals.fromMap(row as Map<String, dynamic>),
    ];
  }

  /// Totais do jogador logado em cada time em que é atleta; com [season], só
  /// os jogos da temporada.
  Future<List<MyTeamTotals>> myTotals({Season? season}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'my_player_totals',
      params: {
        'p_from': season?.start.toUtc().toIso8601String(),
        'p_to': season?.end.toUtc().toIso8601String(),
      },
    );
    return [
      for (final row in rows) MyTeamTotals.fromMap(row as Map<String, dynamic>),
    ];
  }
}

final playerStatsRepositoryProvider = Provider<PlayerStatsRepository>(
  (ref) => PlayerStatsRepository(ref.watch(supabaseClientProvider)),
);

/// Súmula do jogo.
final gameStatsProvider = FutureProvider.autoDispose
    .family<List<PlayerGameStats>, String>(
      (ref, gameId) =>
          ref.watch(playerStatsRepositoryProvider).fetchGame(gameId),
    );

/// Totais dos atletas do time.
final teamPlayerTotalsProvider = FutureProvider.autoDispose
    .family<List<AthleteTotals>, String>(
      (ref, teamId) => ref
          .watch(playerStatsRepositoryProvider)
          .teamTotals(teamId, season: ref.watch(seasonProvider)),
    );

/// Números do jogador logado em cada um dos seus times.
final myTotalsProvider = FutureProvider.autoDispose<List<MyTeamTotals>>(
  (ref) => ref
      .watch(playerStatsRepositoryProvider)
      .myTotals(season: ref.watch(seasonProvider)),
);
