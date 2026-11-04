import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/team_dues.dart';

class DuesRepository {
  DuesRepository(this._client);

  final SupabaseClient _client;

  /// A mensalidade do time; nula se o time não cobra.
  Future<TeamDues?> fetch(String teamId) async {
    final row = await _client
        .from('team_dues')
        .select()
        .eq('team_id', teamId)
        .maybeSingle();
    return row == null ? null : TeamDues.fromMap(row);
  }

  /// Cria ou altera a mensalidade do time.
  Future<void> save(TeamDues dues) =>
      _client.from('team_dues').upsert(dues.toMap());

  /// Para de cobrar (os pagamentos marcados também saem).
  Future<void> delete(String teamId) async {
    await _client.from('team_due_payments').delete().eq('team_id', teamId);
    await _client.from('team_dues').delete().eq('team_id', teamId);
  }

  /// Todos os pagamentos do time ([duePaymentKey]).
  Future<DuePayments> fetchPayments(String teamId) async {
    final rows = await _client
        .from('team_due_payments')
        .select('athlete_id, month')
        .eq('team_id', teamId);
    return {
      for (final row in rows)
        duePaymentKey(
          row['athlete_id'] as String,
          DateTime.parse(row['month'] as String),
        ),
    };
  }

  /// Marca ([paid]) ou desmarca o mês do atleta.
  Future<void> setPaid({
    required String teamId,
    required String athleteId,
    required DateTime month,
    required bool paid,
  }) async {
    final day = '${month.year}-${month.month.toString().padLeft(2, '0')}-01';
    if (paid) {
      await _client.from('team_due_payments').insert({
        'team_id': teamId,
        'athlete_id': athleteId,
        'month': day,
      });
      return;
    }
    await _client
        .from('team_due_payments')
        .delete()
        .eq('athlete_id', athleteId)
        .eq('month', day);
  }
}

final duesRepositoryProvider = Provider<DuesRepository>(
  (ref) => DuesRepository(ref.watch(supabaseClientProvider)),
);

/// Mensalidade do time (nula se não cobra).
final teamDuesProvider = FutureProvider.autoDispose.family<TeamDues?, String>(
  (ref, teamId) => ref.watch(duesRepositoryProvider).fetch(teamId),
);

/// Pagamentos da mensalidade do time.
final duePaymentsProvider = FutureProvider.autoDispose
    .family<DuePayments, String>(
      (ref, teamId) => ref.watch(duesRepositoryProvider).fetchPayments(teamId),
    );
