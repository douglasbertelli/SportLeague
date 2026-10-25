import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/game.dart';
import '../domain/match_clock.dart';

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

  /// Relógio da partida, com a hora do servidor (só quem marcou).
  /// [periodMinutes] é a duração de cada tempo, ao iniciar.
  Future<void> clock(String gameId, ClockAction action, {int? periodMinutes}) =>
      _client.rpc(
        'game_clock',
        params: {
          'p_game': gameId,
          'p_action': switch (action) {
            ClockAction.start => 'start',
            ClockAction.pause => 'pause',
            ClockAction.resume => 'resume',
            ClockAction.endHalf => 'end_half',
            ClockAction.startSecond => 'start_second',
            ClockAction.finish => 'finish',
            ClockAction.reset => 'reset',
          },
          'p_period_minutes': periodMinutes,
        },
      );

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

/// Jogos de um time. Some quando ninguém mais olha: ao trocar de time (dois
/// times do mesmo administrador jogando entre si, ou o adversário lançando o
/// placar), o outro time busca de novo em vez de mostrar dados antigos.
final teamGamesProvider = FutureProvider.autoDispose.family<List<Game>, String>(
  (ref, teamId) => ref.watch(gameRepositoryProvider).fetchByTeam(teamId),
);
