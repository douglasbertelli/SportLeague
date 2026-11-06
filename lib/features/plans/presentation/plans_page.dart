import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fundraisers/domain/fundraiser.dart' show formatMoney;
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
              for (final plan in SubscriptionPlan.values) ...[
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final premium = plan == SubscriptionPlan.premium;
    final current = status?.plan == plan;
    final price = this.price;
    final teams = status?.usage[PlanFeature.teams] ?? 0;
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
            if (price != null) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: price.isFree
                          ? 'Grátis'
                          : formatMoney(price.monthlyCents),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!price.isFree)
                      TextSpan(
                        text: ' por mês',
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              if (price.extraTeamCents > 0)
                Text(
                  'Com 1 time. Cada time a mais: + '
                  '${formatMoney(price.extraTeamCents)} por mês.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              // O que o administrador pagaria com os times que já tem.
              if (premium && !price.isFree && teams > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Com os seus $teams times: '
                    '${formatMoney(price.totalFor(teams))} por mês.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            // Só o que o plano inclui (o não incluso fica de fora).
            for (final feature in PlanFeature.values)
              if (_row(feature)?.quota != 0)
                _FeatureLine(
                  feature: feature,
                  quota: _row(feature)?.quota,
                  description: _row(feature)?.description,
                  extraTeamCents: price?.extraTeamCents ?? 0,
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
              OutlinedButton(
                onPressed: null,
                child: const Text('Assinatura em breve'),
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
  const _FeatureLine({
    required this.feature,
    required this.quota,
    this.description,
    this.extraTeamCents = 0,
  });

  final PlanFeature feature;
  final Quota quota;

  /// Texto do plano (do banco); nulo usa o padrão da funcionalidade.
  final String? description;

  /// Preço de cada time a mais (para o rótulo de Times).
  final int extraTeamCents;

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
            describeQuota(feature, quota, extraTeamCents: extraTeamCents),
            style: theme.textTheme.labelLarge?.copyWith(
              color: included ? null : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
