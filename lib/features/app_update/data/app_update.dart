import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Versão mínima da plataforma (tabela `app_versions`).
typedef MinVersion = ({int minBuild, String? storeUrl});

/// Se o build instalado ([currentBuild]) está abaixo do mínimo.
bool isUpdateRequired({required int currentBuild, required int minBuild}) =>
    currentBuild < minBuild;

/// Plataforma na tabela `app_versions`; nula fora do Android e do iOS (web,
/// desktop e testes não são bloqueados).
String? appVersionPlatform() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}

/// Versão mínima da plataforma; nula sem linha, fora do Android e do iOS ou
/// com erro (sem rede, por exemplo): nesses casos o app não bloqueia.
final minVersionProvider = FutureProvider<MinVersion?>((ref) async {
  final platform = appVersionPlatform();
  if (platform == null) return null;
  try {
    final row = await ref
        .read(supabaseClientProvider)
        .from('app_versions')
        .select('min_build, store_url')
        .eq('platform', platform)
        .maybeSingle();
    if (row == null) return null;
    return (
      minBuild: row['min_build'] as int? ?? 0,
      storeUrl: row['store_url'] as String?,
    );
  } catch (_) {
    return null;
  }
});

/// Build instalado (o número depois do "+" da versão); nulo se não der para
/// ler.
final currentBuildProvider = FutureProvider<int?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber);
  } catch (_) {
    return null;
  }
});

/// Se o app precisa ser atualizado antes de usar. Falso enquanto carrega e
/// quando não dá para saber (nunca bloqueia por falta de informação).
final updateRequiredProvider = Provider<bool>((ref) {
  final min = ref.watch(minVersionProvider).value;
  final current = ref.watch(currentBuildProvider).value;
  if (min == null || current == null) return false;
  return isUpdateRequired(currentBuild: current, minBuild: min.minBuild);
});
