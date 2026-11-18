import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/routes.dart';
import '../../fundraisers/domain/fundraiser.dart' show formatMoney;
import '../../profile/domain/profile.dart';
import '../data/plan_repository.dart';
import '../data/store_billing.dart';
import '../domain/plan_status.dart';
import 'billing_visibility.dart';
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
              // O Vip só aparece para quem está nele, e sozinho.
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

  /// O Vip tem tudo liberado e sem limite.
  Quota _quota(PlanFeature feature) =>
      plan == SubscriptionPlan.elite ? null : _row(feature)?.quota;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final premium = plan == SubscriptionPlan.premium;
    final elite = plan == SubscriptionPlan.elite;
    final current = status?.plan == plan;
    final price = this.price;
    final teams = status?.usage[PlanFeature.teams] ?? 0;
    final trialDays = price?.trialDays;
    // O teste grátis sem cartão é do site; no app, a loja.
    final canTry =
        billingVisible &&
        premium &&
        (status?.trialAvailable ?? false) &&
        trialDays != null;
    // No app das lojas vale o preço da loja (pode ter centavos diferentes).
    final storePrice = premium && StoreBilling.available
        ? ref.watch(premiumStoreProductProvider).value?.price.localizedString
        : null;

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
            if (price != null) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: price.isFree
                          ? 'Grátis'
                          : storePrice ?? formatMoney(price.monthlyCents),
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
              // O que o administrador pagaria com os times que já tem (só se
              // houver cobrança por time a mais).
              if (premium && price.extraTeamCents > 0 && teams > 1)
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
            if (elite) ...[
              const SizedBox(height: 8),
              Text(
                'Sem cobrança',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Sem mensalidade e com todas as funcionalidades liberadas.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Só o que o plano inclui (o não incluso fica de fora).
            for (final feature in PlanFeature.values)
              if (_quota(feature) != 0)
                _FeatureLine(
                  feature: feature,
                  quota: _quota(feature),
                  description: _row(feature)?.description,
                  extraTeamCents: price?.extraTeamCents ?? 0,
                ),
            if (premium && status?.paidPlan == SubscriptionPlan.premium)
              _ManageSubscription(source: status?.billingSource)
            else if (premium && status?.paidPlan != SubscriptionPlan.elite) ...[
              const SizedBox(height: 16),
              if (canTry) ...[
                FilledButton.icon(
                  onPressed: () => startPremiumTrial(context, ref, trialDays),
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: Text('Testar grátis por $trialDays dias'),
                ),
                const SizedBox(height: 8),
              ],
              if (StoreBilling.available)
                const _StoreSubscribe()
              else ...[
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
            // "+ R$ 10,00" e, embaixo, "por time": alinhados à direita.
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

/// Assinar o Premium pela loja (App Store / Google Play), no app.
class _StoreSubscribe extends ConsumerStatefulWidget {
  const _StoreSubscribe();

  @override
  ConsumerState<_StoreSubscribe> createState() => _StoreSubscribeState();
}

class _StoreSubscribeState extends ConsumerState<_StoreSubscribe> {
  bool _busy = false;

  /// O Premium é liberado pelo servidor quando o aviso da loja chega: lê o
  /// plano de novo por alguns segundos.
  Future<bool> _waitForPremium() async {
    for (var i = 0; i < 10; i++) {
      final status = await ref.refresh(planStatusProvider.future);
      if (status.paidPlan == SubscriptionPlan.premium) return true;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return false;
  }

  Future<void> _run(Future<bool> Function() action, String doneMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (!await action()) return;
      final released = await _waitForPremium();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            released
                ? doneMessage
                : 'Pagamento confirmado. O Premium é liberado em instantes.',
          ),
        ),
      );
    } on StorePurchasePending {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Pagamento pendente na loja. O Premium é liberado quando for '
            'aprovado.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível concluir. Tente novamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final product = ref.watch(premiumStoreProductProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (product) {
          AsyncData(value: final product?) => FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => StoreBilling.instance.buy(product),
                    'Premium liberado!',
                  ),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.workspace_premium_outlined),
            label: Text(
              'Assinar por ${product.price.localizedString ?? ''}/mês',
            ),
          ),
          AsyncLoading() => const FilledButton(
            onPressed: null,
            child: Text('Carregando a loja…'),
          ),
          _ => OutlinedButton.icon(
            onPressed: () => ref.invalidate(premiumStoreProductProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Loja indisponível. Tentar de novo'),
          ),
        },
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(
                  StoreBilling.instance.restore,
                  'Assinatura restaurada.',
                ),
          child: const Text('Restaurar compras'),
        ),
        Text(
          'Cobrança mensal pela sua conta da loja, renovada automaticamente. '
          'Cancele quando quiser nas assinaturas da loja.',
          textAlign: TextAlign.center,
          style: muted,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => context.push(Routes.terms),
              child: const Text('Termos de uso'),
            ),
            TextButton(
              onPressed: () => context.push(Routes.privacy),
              child: const Text('Privacidade'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Quem já assina: onde gerenciar.
class _ManageSubscription extends StatelessWidget {
  const _ManageSubscription({required this.source});

  final BillingSource? source;

  static Uri get _storeSubscriptions => Uri.parse(
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(text, textAlign: TextAlign.center, style: muted),
    );
    return switch (source) {
      // Assinada pela loja: no app, abre as assinaturas da loja.
      BillingSource.store when isStoreApp => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: OutlinedButton.icon(
          onPressed: () => launchUrl(
            _storeSubscriptions,
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Gerenciar assinatura'),
        ),
      ),
      BillingSource.store => note(
        'Assinatura feita pelo app. Gerencie nas assinaturas da loja do seu '
        'celular.',
      ),
      // Assinada pelo site: no app, só o aviso (sem link).
      BillingSource.asaas when isStoreApp => note(
        'Assinatura feita pelo site.',
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
