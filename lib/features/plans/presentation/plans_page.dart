import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/domain/profile.dart';
import '../data/plan_repository.dart';
import '../domain/plan_status.dart';

/// Comparação dos planos. Os limites vêm da tabela `plan_features` do banco;
/// mudar um limite lá muda esta tela sem versão nova do app.
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(planFeaturesProvider);
    final current = ref.watch(planStatusProvider).value?.plan;

    return Scaffold(
      appBar: AppBar(title: const Text('Planos')),
      body: features.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(planFeaturesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os planos. Tentar novamente'),
          ),
        ),
        data: (rows) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final plan in SubscriptionPlan.values) ...[
              _PlanCard(
                plan: plan,
                rows: rows.where((row) => row.plan == plan).toList(),
                current: plan == current,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Os jogadores e técnicos usam o app de graça. O plano é do '
              'administrador e vale para os times dele.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.rows,
    required this.current,
  });

  final SubscriptionPlan plan;
  final List<PlanFeatureRow> rows;
  final bool current;

  Quota _quota(PlanFeature feature) =>
      rows.where((row) => row.feature == feature).firstOrNull?.quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final premium = plan == SubscriptionPlan.premium;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: current
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  premium
                      ? Icons.workspace_premium_outlined
                      : Icons.sports_soccer_outlined,
                  color: premium ? scheme.tertiary : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.label, style: theme.textTheme.titleLarge),
                ),
                if (current)
                  Chip(
                    label: const Text('Seu plano'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: scheme.primaryContainer,
                    labelStyle: TextStyle(color: scheme.onPrimaryContainer),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final feature in PlanFeature.values)
              _FeatureLine(feature: feature, quota: _quota(feature)),
            if (premium && !current) ...[
              const SizedBox(height: 16),
              const FilledButton(
                onPressed: null,
                child: Text('Assinatura em breve'),
              ),
              const SizedBox(height: 4),
              Text(
                'A assinatura ainda não está disponível no app.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.feature, required this.quota});

  final PlanFeature feature;
  final Quota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final included = quota != 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            included ? Icons.check_circle : Icons.remove_circle_outline,
            size: 20,
            color: included ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.label, style: theme.textTheme.bodyLarge),
                Text(
                  feature.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            describeQuota(feature, quota),
            style: theme.textTheme.labelLarge?.copyWith(
              color: included ? null : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
