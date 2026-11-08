import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../fundraisers/domain/fundraiser.dart' show formatMoney;
import '../../profile/domain/profile.dart';
import '../data/plan_repository.dart';
import '../domain/plan_status.dart';
import '../domain/subscription_payment.dart';
import 'plan_gate.dart' show formatDayMonth;

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// "nov/2026".
String _monthYear(DateTime at) => '${_months[at.month - 1]}/${at.year}';

/// "08/11/2026".
String _date(DateTime at) =>
    '${at.day.toString().padLeft(2, '0')}/'
    '${at.month.toString().padLeft(2, '0')}/${at.year}';

/// Financeiro do administrador: o plano, quanto custa por mês com os times
/// dele e os pagamentos da assinatura.
class FinancePage extends ConsumerWidget {
  const FinancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(planStatusProvider);
    final prices = ref.watch(planPricesProvider);
    final payments = ref.watch(subscriptionPaymentsProvider);

    void retry() => ref
      ..invalidate(planStatusProvider)
      ..invalidate(planPricesProvider)
      ..invalidate(subscriptionPaymentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Financeiro')),
      body: switch ((status, prices, payments)) {
        (AsyncValue(hasError: true), _, _) ||
        (_, AsyncValue(hasError: true), _) ||
        (_, _, AsyncValue(hasError: true)) => Center(
          child: TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar. Tentar novamente'),
          ),
        ),
        (
          AsyncData(value: final status),
          AsyncData(value: final prices),
          AsyncData(value: final payments),
        ) =>
          RefreshIndicator(
            onRefresh: () async => retry(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _PlanCard(status: status),
                const SizedBox(height: 12),
                if (prices
                        .where((p) => p.plan == SubscriptionPlan.premium)
                        .firstOrNull
                    case final premium?)
                  _MonthlyCard(status: status, price: premium),
                const SizedBox(height: 12),
                _SummaryCard(payments: payments),
                const SizedBox(height: 24),
                Text(
                  'Pagamentos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (payments.isEmpty)
                  const _NoPayments()
                else
                  for (final payment in payments)
                    _PaymentTile(payment: payment),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.status});

  final PlanStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final premium = status.plan == SubscriptionPlan.premium;
    final subtitle = switch (status) {
      PlanStatus(trialEndsAt: final ends?) =>
        'Teste grátis até ${formatDayMonth(ends)}',
      PlanStatus(paidPlan: SubscriptionPlan.premium) => 'Assinatura ativa',
      _ => 'Sem assinatura',
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: premium
              ? colors.tertiaryContainer
              : colors.secondaryContainer,
          child: Icon(
            premium
                ? Icons.workspace_premium_outlined
                : Icons.sports_soccer_outlined,
            color: premium
                ? colors.onTertiaryContainer
                : colors.onSecondaryContainer,
          ),
        ),
        title: Text('Plano ${status.plan.label}'),
        subtitle: Text(subtitle),
        trailing: TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => context.push(Routes.plans),
          child: const Text('Ver planos'),
        ),
      ),
    );
  }
}

/// Quanto o Premium custa por mês com os times ativos do administrador.
class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard({required this.status, required this.price});

  final PlanStatus status;
  final PlanPrice price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final teams = status.usage[PlanFeature.teams] ?? 0;
    final extra = teams > 1 ? teams - 1 : 0;
    final subscribed = status.paidPlan == SubscriptionPlan.premium;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    Widget line(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong ? theme.textTheme.titleSmall : muted,
            ),
          ),
          Text(
            value,
            style: strong
                ? theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              subscribed ? 'Valor mensal' : 'Valor do Premium com seus times',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            line('Mensalidade (com 1 time)', formatMoney(price.monthlyCents)),
            line(
              extra == 1
                  ? '1 time a mais × ${formatMoney(price.extraTeamCents)}'
                  : '$extra times a mais × ${formatMoney(price.extraTeamCents)}',
              formatMoney(price.extraTeamCents * extra),
            ),
            const Divider(),
            line(
              'Total por mês',
              formatMoney(price.totalFor(teams)),
              strong: true,
            ),
            const SizedBox(height: 8),
            Text(
              teams == 1
                  ? 'Calculado com o seu time ativo.'
                  : 'Calculado com os seus $teams times ativos. Times '
                        'inativos não são cobrados.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (!subscribed) ...[
              const SizedBox(height: 4),
              Text(
                'A assinatura ainda não está disponível no app.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.payments});

  final List<SubscriptionPayment> payments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (:totalPaidCents, :lastPaid) = summarizePayments(payments);

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            stat('Total pago', formatMoney(totalPaidCents)),
            stat(
              'Último pagamento',
              lastPaid == null ? '—' : _monthYear(lastPaid.periodStart),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final SubscriptionPayment payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (background, foreground) = switch (payment.status) {
      PaymentStatus.paid => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      PaymentStatus.pending => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      PaymentStatus.failed => (colors.errorContainer, colors.onErrorContainer),
      PaymentStatus.refunded => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text('Premium · ${_monthYear(payment.periodStart)}'),
        subtitle: Text(
          [
            payment.teams == 1 ? '1 time' : '${payment.teams} times',
            ?payment.method,
            if (payment.paidAt case final at?) 'pago em ${_date(at)}',
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(payment.amountCents),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                payment.status.label,
                style: theme.textTheme.labelSmall?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPayments extends StatelessWidget {
  const _NoPayments();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text('Nenhum pagamento ainda', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Os pagamentos da assinatura aparecem aqui, mês a mês.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
