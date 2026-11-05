import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/app_sheet.dart';
import '../data/plan_repository.dart';
import '../domain/plan_status.dart';

/// Explica que a funcionalidade é do Premium, com o atalho para os planos.
Future<void> showPremiumSheet(
  BuildContext context,
  PlanFeature feature, {
  Quota quota,
}) => showAppSheet<void>(
  context,
  builder: (sheetContext) => AppSheet(
    title: 'Recurso do plano Premium',
    message: planLimitMessage(feature, quota),
    actions: [
      FilledButton.icon(
        onPressed: () {
          Navigator.of(sheetContext).pop();
          context.push(Routes.plans);
        },
        icon: const Icon(Icons.workspace_premium_outlined),
        label: const Text('Ver planos'),
      ),
      TextButton(
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: const Text('Agora não'),
      ),
    ],
  ),
);

/// Confere o plano antes de criar (times, campeonatos) ou de usar uma
/// funcionalidade. Sem permissão, mostra o aviso e devolve `false`.
/// Busca o uso atualizado a cada vez (times e campeonatos criados ou
/// apagados em outro lugar). Se o plano não carregar, deixa seguir: o banco
/// barra de qualquer jeito.
Future<bool> ensurePlanAllows(
  BuildContext context,
  WidgetRef ref,
  PlanFeature feature, {
  bool adding = false,
}) async {
  PlanStatus status;
  try {
    status = await ref.refresh(planStatusProvider.future);
  } catch (_) {
    return true;
  }
  final allowed = adding ? status.canAdd(feature) : status.has(feature);
  if (!allowed && context.mounted) {
    await showPremiumSheet(context, feature, quota: status.quota(feature));
  }
  return allowed;
}

/// Mostra o aviso do Premium quando o erro é o limite do plano vindo do
/// banco. Devolve `true` se tratou o erro.
bool handlePlanLimitError(BuildContext context, Object error) {
  final feature = planLimitFeature(error.toString());
  if (feature == null) return false;
  showPremiumSheet(context, feature);
  return true;
}

/// Selo "Premium" para opções bloqueadas.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_outlined,
            size: 14,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'Premium',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onTertiaryContainer),
          ),
        ],
      ),
    );
  }
}
