import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/fundraisers/domain/fundraiser.dart'
    show formatMoney;
import 'package:sport_league/features/plans/data/plan_repository.dart';
import 'package:sport_league/features/plans/domain/plan_status.dart';
import 'package:sport_league/features/plans/domain/subscription_payment.dart';
import 'package:sport_league/features/plans/presentation/finance_page.dart';
import 'package:sport_league/features/profile/domain/profile.dart';

const _premium = PlanPrice(
  plan: SubscriptionPlan.premium,
  monthlyCents: 3000,
  extraTeamCents: 1500,
  trialDays: 15,
);

SubscriptionPayment _payment(String id, int month, PaymentStatus status) =>
    SubscriptionPayment.fromMap({
      'id': id,
      'plan': 'premium',
      'amount_cents': 6000,
      'teams': 3,
      'period_start': '2026-${month.toString().padLeft(2, '0')}-01',
      'period_end': '2026-${month.toString().padLeft(2, '0')}-28',
      'status': status.name,
      'method': 'Pix',
      'paid_at': status == PaymentStatus.paid
          ? '2026-${month.toString().padLeft(2, '0')}-05T12:00:00Z'
          : null,
    });

Future<void> _pump(
  WidgetTester tester, {
  required PlanStatus status,
  List<SubscriptionPayment> payments = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planStatusProvider.overrideWith((ref) async => status),
        planPricesProvider.overrideWith((ref) async => const [_premium]),
        subscriptionPaymentsProvider.overrideWith((ref) async => payments),
      ],
      child: const MaterialApp(home: FinancePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('resumo: total pago e último pagamento', () {
    final summary = summarizePayments([
      _payment('a', 9, PaymentStatus.paid),
      _payment('b', 10, PaymentStatus.paid),
      _payment('c', 11, PaymentStatus.failed),
    ]);
    expect(summary.totalPaidCents, 12000);
    expect(summary.lastPaid?.id, 'b');
  });

  testWidgets(
    'sem assinatura: valor do Premium com os times e sem pagamentos',
    (tester) async {
      await _pump(
        tester,
        status: const PlanStatus(
          plan: SubscriptionPlan.free,
          paidPlan: SubscriptionPlan.free,
          usage: {PlanFeature.teams: 3},
        ),
      );
      expect(find.text('Plano Gratuito'), findsOneWidget);
      expect(find.text('Sem assinatura'), findsOneWidget);
      expect(find.text('Valor do Premium com seus times'), findsOneWidget);
      // R$ 30 + 2 × R$ 15 = R$ 60.
      expect(find.text(formatMoney(6000)), findsOneWidget);
      expect(find.text('Nenhum pagamento ainda'), findsOneWidget);
    },
  );

  testWidgets('assinante: lista os pagamentos com a situação', (tester) async {
    await _pump(
      tester,
      status: const PlanStatus(
        plan: SubscriptionPlan.premium,
        paidPlan: SubscriptionPlan.premium,
        usage: {PlanFeature.teams: 1},
      ),
      payments: [
        _payment('b', 10, PaymentStatus.paid),
        _payment('c', 11, PaymentStatus.failed),
      ],
    );
    expect(find.text('Assinatura ativa'), findsOneWidget);
    expect(find.text('Valor mensal'), findsOneWidget);
    expect(find.text('Premium · out/2026'), findsOneWidget);
    expect(find.text('Premium · nov/2026'), findsOneWidget);
    expect(find.text('Pago'), findsOneWidget);
    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('out/2026'), findsOneWidget);
  });
}
