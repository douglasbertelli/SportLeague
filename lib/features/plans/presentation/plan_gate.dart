import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../profile/domain/profile.dart';
import '../data/plan_repository.dart';
import '../domain/plan_status.dart';

/// Explica que a funcionalidade é do Premium, com o atalho para os planos
/// (e para o teste grátis, se ainda não usou).
Future<void> showPremiumSheet(
  BuildContext context,
  PlanFeature feature, {
  Quota quota,
}) => showAppSheet<void>(
  context,
  builder: (sheetContext) => Consumer(
    builder: (sheetContext, ref, _) {
      final status = ref.watch(planStatusProvider).value;
      // No Elite o limite é combinado com cada cliente: não há plano para
      // oferecer.
      if (status?.plan == SubscriptionPlan.elite) {
        return AppSheet(
          title: 'Limite do seu plano',
          message: eliteLimitMessage(feature, quota ?? status!.quota(feature)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Entendi'),
            ),
          ],
        );
      }
      final trialAvailable = status?.trialAvailable ?? false;
      final trialDays = _premiumPrice(ref)?.trialDays;
      final canTry = trialAvailable && trialDays != null;
      return AppSheet(
        title: 'Recurso do plano Premium',
        message: planLimitMessage(feature, quota),
        actions: [
          if (canTry)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                startPremiumTrial(context, ref, trialDays);
              },
              icon: const Icon(Icons.rocket_launch_outlined),
              label: Text('Testar grátis por $trialDays dias'),
            ),
          if (canTry)
            OutlinedButton(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.push(Routes.plans);
              },
              child: const Text('Ver planos'),
            )
          else
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
      );
    },
  ),
);

PlanPrice? _premiumPrice(WidgetRef ref) => ref
    .watch(planPricesProvider)
    .value
    ?.where((price) => price.plan == SubscriptionPlan.premium)
    .firstOrNull;

/// Confirma e começa o teste grátis do Premium.
Future<void> startPremiumTrial(
  BuildContext context,
  WidgetRef ref,
  int days,
) async {
  final confirmed = await showAppSheet<bool>(
    context,
    builder: (sheetContext) => AppSheet(
      title: 'Testar o Premium por $days dias?',
      message:
          'Tudo do Premium fica liberado por $days dias, sem cobrança. No '
          'fim, sua conta volta sozinha para o plano Gratuito e nada é '
          'apagado. O teste só pode ser usado uma vez.',
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(sheetContext).pop(true),
          child: const Text('Começar teste'),
        ),
        TextButton(
          onPressed: () => Navigator.of(sheetContext).pop(false),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ends = await ref.read(planRepositoryProvider).startTrial();
    ref.invalidate(planStatusProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('Premium liberado até ${formatDayMonth(ends)}.')),
    );
  } catch (error) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Não foi possível começar o teste. Tente novamente.'),
      ),
    );
  }
}

/// "20/11".
String formatDayMonth(DateTime at) =>
    '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}';

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
