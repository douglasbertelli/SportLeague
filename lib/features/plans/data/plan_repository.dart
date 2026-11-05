import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/plan_status.dart';

class PlanRepository {
  PlanRepository(this._client);

  final SupabaseClient _client;

  /// Plano, limites e uso do usuário logado.
  Future<PlanStatus> fetchStatus() async {
    final map = await _client.rpc<Map<String, dynamic>?>('plan_status');
    return map == null ? PlanStatus.unrestricted : PlanStatus.fromMap(map);
  }

  /// Todos os limites de todos os planos (para a comparação).
  Future<List<PlanFeatureRow>> fetchFeatures() async {
    final rows = await _client.from('plan_features').select();
    return rows.map(PlanFeatureRow.fromMap).toList();
  }
}

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => PlanRepository(ref.watch(supabaseClientProvider)),
);

/// Plano do usuário logado. Invalide depois de criar ou apagar times e
/// campeonatos, para o uso ficar certo.
final planStatusProvider = FutureProvider<PlanStatus>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return PlanStatus.unrestricted;
  return ref.watch(planRepositoryProvider).fetchStatus();
});

final planFeaturesProvider = FutureProvider.autoDispose<List<PlanFeatureRow>>(
  (ref) => ref.watch(planRepositoryProvider).fetchFeatures(),
);
