import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/domain/profile.dart';
import '../data/plan_repository.dart';
import '../domain/plan_status.dart';
import 'plan_gate.dart';

/// Comparação dos planos. Os limites (`plan_features`) e os preços (`plans`)
/// vêm do banco; mudar lá muda esta tela sem versão nova do app.
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final features = ref.watch(planFeaturesProvider);
    final prices = ref.watch(planPricesProvider);
    final status = ref.watch(planStatusProvider).value;

    void retry() => ref
      ..invalidate(planFeaturesProvider)
      ..invalidate(planPricesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Planos')),
      body: switch ((features, prices)) {
        (AsyncValue(hasError: true), _) ||
        (_, AsyncValue(hasError: true)) => Center(
          child: TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os planos. Tentar novamente'),
          ),
        ),
        (AsyncData(value: final rows), AsyncData(value: final prices)) =>
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (status?.trialEndsAt case final ends?) ...[
                _TrialBanner(ends: ends),
                const SizedBox(height: 16),
              ],
              // O Elite só aparece para quem está nele, e sozinho.
              for (final plan
                  in status?.plan == SubscriptionPlan.elite
                      ? const [SubscriptionPlan.elite]
                      : SubscriptionPlan.values.where(
                          (plan) => plan != SubscriptionPlan.elite,
                        )) ...[
                _PlanCard(
                  plan: plan,
                  rows: rows.where((row) => row.plan == plan).toList(),
                  price: prices.where((p) => p.plan == plan).firstOrNull,
                  status: status,
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
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TrialBanner extends StatelessWidget {
  const _TrialBanner({required this.ends});

  final DateTime ends;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.tertiaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.rocket_launch_outlined,
          color: colors.onTertiaryContainer,
        ),
        title: Text('Teste do Premium até ${formatDayMonth(ends)}'),
        subtitle: const Text(
          'Depois, sua conta volta para o Gratuito. Nada é apagado.',
        ),
        textColor: colors.onTertiaryContainer,
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.rows,
    required this.price,
    required this.status,
  });

  final SubscriptionPlan plan;
  final List<PlanFeatureRow> rows;
  final PlanPrice? price;
  final PlanStatus? status;

  PlanFeatureRow? _row(PlanFeature feature) =>
      rows.where((row) => row.feature == feature).firstOrNull;

  Quota _quota(PlanFeature feature) => plan == SubscriptionPlan.elite
      ? status?.quota(feature)
      : _row(feature)?.quota;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final premium = plan == SubscriptionPlan.premium;
    final elite = plan == SubscriptionPlan.elite;
    final current = status?.plan == plan;
    final price = this.price;
    final trialDays = price?.trialDays;
    final canTry =
        premium && (status?.trialAvailable ?? false) && trialDays != null;

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
                  elite
                      ? Icons.diamond_outlined
                      : premium
                      ? Icons.workspace_premium_outlined
                      : Icons.sports_soccer_outlined,
                  color: premium || elite ? scheme.tertiary : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.label, style: theme.textTheme.titleLarge),
                ),
                if (current)
                  Chip(
                    label: Text(
                      premium && (status?.onTrial ?? false)
                          ? 'Em teste'
                          : 'Seu plano',
                    ),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: scheme.primaryContainer,
                    labelStyle: TextStyle(color: scheme.onPrimaryContainer),
                  ),
              ],
            ),
            if (elite) ...[
              const SizedBox(height: 8),
              Text(
                'Todas as funcionalidades liberadas, com os limites '
                'combinados com você.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Só o que o plano inclui (o não incluso fica de fora).
            // No Elite os limites são os do cliente (plan_status), não os
            // da tabela de planos.
            for (final feature in PlanFeature.values)
              if (_quota(feature) != 0)
                _FeatureLine(
                  feature: feature,
                  quota: _quota(feature),
                  description: _row(feature)?.description,
                ),
            if (premium && status?.paidPlan != SubscriptionPlan.premium) ...[
              const SizedBox(height: 16),
              if (canTry) ...[
                FilledButton.icon(
                  onPressed: () => startPremiumTrial(context, ref, trialDays),
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: Text('Testar grátis por $trialDays dias'),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({
    required this.feature,
    required this.quota,
    this.description,
  });

  final PlanFeature feature;
  final Quota quota;

  /// Texto do plano (do banco); nulo usa o padrão da funcionalidade.
  final String? description;

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
                  description ?? feature.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            // Sem preço no app (regra das lojas): Times do Premium é
            // "Vários times".
            describeQuota(feature, quota),
            textAlign: TextAlign.end,
            style: theme.textTheme.labelLarge?.copyWith(
              color: included ? null : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
