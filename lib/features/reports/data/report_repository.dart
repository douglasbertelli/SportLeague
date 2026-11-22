import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/content_report.dart';

class ReportRepository {
  ReportRepository(this._client);

  final SupabaseClient _client;

  /// Envia a denúncia para análise. Denunciar de novo o mesmo conteúdo, com a
  /// anterior ainda aberta, não cria outra.
  Future<void> report({
    required ReportTarget target,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) => _client.rpc<void>(
    'report_content',
    params: {
      'p_target_type': target.name,
      'p_target_id': targetId,
      'p_reason': reason.name,
      'p_details': details,
    },
  );
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(supabaseClientProvider)),
);
