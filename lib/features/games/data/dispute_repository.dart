import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/score_dispute.dart';

class DisputeRepository {
  DisputeRepository(this._client);

  final SupabaseClient _client;

  /// Contestações abertas que o time fez ou recebeu (como quem marcou).
  /// A RLS já limita às do administrador; aqui fica só o time pedido (ele
  /// pode ter outros times).
  Future<List<ScoreDispute>> openForTeam(String teamId) async {
    final rows = await _client
        .from('score_disputes')
        .select('*, game:games(team_id)')
        .eq('status', 'open')
        .order('created_at');
    return [
      for (final row in rows)
        if (row['team_id'] == teamId ||
            (row['game'] as Map<String, dynamic>?)?['team_id'] == teamId)
          ScoreDispute.fromMap(row),
    ];
  }

  /// O adversário contesta o placar.
  Future<void> create(ScoreDispute dispute) =>
      _client.from('score_disputes').insert(dispute.toMap());

  /// Quem marcou aceita (o placar passa a ser o contestado) ou mantém o dele.
  Future<void> resolve(String disputeId, {required bool accept}) => _client.rpc(
    'resolve_score_dispute',
    params: {'p_dispute': disputeId, 'p_accept': accept},
  );
}

final disputeRepositoryProvider = Provider<DisputeRepository>(
  (ref) => DisputeRepository(ref.watch(supabaseClientProvider)),
);

/// Contestações abertas do time (feitas ou recebidas).
final teamDisputesProvider = FutureProvider.autoDispose
    .family<List<ScoreDispute>, String>(
      (ref, teamId) => ref.watch(disputeRepositoryProvider).openForTeam(teamId),
    );
