import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/presence_answer.dart';

/// Resposta de um atleta ao pedido de presença: [answer] nulo é sem resposta.
typedef PresenceEntry = ({
  String athleteId,
  String name,
  PresenceAnswer? answer,
});

class PresenceRepository {
  PresenceRepository(this._client);

  final SupabaseClient _client;

  /// O dono ou o técnico pede a confirmação; devolve quantos foram avisados.
  Future<int> request(String gameId, String teamId) async => await _client.rpc(
    'request_presence',
    params: {'p_game': gameId, 'p_team': teamId},
  ) as int;

  /// O atleta responde Sim, Não ou Talvez.
  Future<void> answer(String gameId, String teamId, PresenceAnswer answer) =>
      _client.rpc(
        'answer_presence',
        params: {'p_game': gameId, 'p_team': teamId, 'p_answer': answer.value},
      );

  /// Respostas do time no jogo (para o dono e o técnico).
  Future<List<PresenceEntry>> fetchGame(String gameId, String teamId) async {
    final rows = await _client
        .from('game_presence')
        .select('athlete_id, answer, athlete:team_players(name)')
        .eq('game_id', gameId)
        .eq('team_id', teamId);
    return [
      for (final row in rows)
        (
          athleteId: row['athlete_id'] as String,
          name:
              (row['athlete'] as Map<String, dynamic>?)?['name'] as String? ??
              'Atleta',
          answer: PresenceAnswer.fromValue(row['answer']),
        ),
    ];
  }

  /// As respostas do usuário logado, por jogo.
  Future<Map<String, PresenceAnswer?>> fetchMine(String userId) async {
    final rows = await _client
        .from('game_presence')
        .select('game_id, answer, athlete:team_players!inner(profile_id)')
        .eq('athlete.profile_id', userId);
    return {
      for (final row in rows)
        row['game_id'] as String: PresenceAnswer.fromValue(row['answer']),
    };
  }
}

final presenceRepositoryProvider = Provider<PresenceRepository>(
  (ref) => PresenceRepository(ref.watch(supabaseClientProvider)),
);

/// Respostas do time no jogo.
final gamePresenceProvider = FutureProvider.autoDispose
    .family<List<PresenceEntry>, ({String gameId, String teamId})>(
      (ref, key) => ref
          .watch(presenceRepositoryProvider)
          .fetchGame(key.gameId, key.teamId),
    );

/// As respostas do jogador logado, por jogo.
final myPresenceProvider =
    FutureProvider.autoDispose<Map<String, PresenceAnswer?>>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return const {};
      return ref.watch(presenceRepositoryProvider).fetchMine(userId);
    });
