import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/plans/data/plan_repository.dart';
import 'package:sport_league/features/plans/domain/plan_status.dart';
import 'package:sport_league/features/plans/presentation/plans_page.dart';

/// As linhas de `banners` como estão no banco de produção (migration
/// 20261111030000_banners.sql).
const _bannersDescription =
    'Crie banners para as redes a partir de modelos (jogo, resultado, '
    'convocação, aniversariante, campeão), com as cores, as fontes e o '
    'escudo do time.';

final _rows = [
  PlanFeatureRow.fromMap({'plan': 'free', 'feature': 'banners', 'quota': 0}),
  PlanFeatureRow.fromMap({
    'plan': 'premium',
    'feature': 'banners',
    'quota': null,
    'description': _bannersDescription,
  }),
];

void main() {
  testWidgets('o Premium mostra os banners e o Gratuito não', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planFeaturesProvider.overrideWith((ref) async => _rows),
          planPricesProvider.overrideWith((ref) async => const []),
          planStatusProvider.overrideWith(
            (ref) async => PlanStatus.fromMap({
              'plan': 'free',
              'quotas': {'banners': 0},
            }),
          ),
        ],
        child: const MaterialApp(home: PlansPage()),
      ),
    );
    await tester.pumpAndSettle();

    final label = find.text('Banners do time');
    await tester.scrollUntilVisible(label, 120);
    // Uma vez só: no cartão do Premium, com o texto do banco.
    expect(label, findsOneWidget);
    expect(find.text(_bannersDescription), findsOneWidget);
    final premiumCard = find.ancestor(of: label, matching: find.byType(Card));
    expect(
      find.descendant(of: premiumCard, matching: find.text('Premium')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: premiumCard, matching: find.text('Gratuito')),
      findsNothing,
    );
  });

  // Regra das lojas: a assinatura é paga fora delas (Asaas, pelo site), então
  // o app não mostra preço nem chama para assinar.
  testWidgets('os planos não mostram preço nem botão de assinar', (
    tester,
  ) async {
    tester.view
      // Alta o bastante para os dois planos aparecerem inteiros.
      ..physicalSize = const Size(1080, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planFeaturesProvider.overrideWith(
            (ref) async => [
              PlanFeatureRow.fromMap({
                'plan': 'free',
                'feature': 'teams',
                'quota': 1,
              }),
              PlanFeatureRow.fromMap({
                'plan': 'premium',
                'feature': 'teams',
                'quota': null,
              }),
            ],
          ),
          planPricesProvider.overrideWith(
            (ref) async => [
              PlanPrice.fromMap({
                'plan': 'free',
                'monthly_cents': 0,
                'extra_team_cents': 0,
              }),
              PlanPrice.fromMap({
                'plan': 'premium',
                'monthly_cents': 3000,
                'extra_team_cents': 1500,
                'trial_days': 15,
              }),
            ],
          ),
          planStatusProvider.overrideWith(
            (ref) async => PlanStatus.fromMap({
              'plan': 'free',
              'quotas': {'teams': 1},
              'usage': {'teams': 3},
              'trial_available': true,
            }),
          ),
        ],
        child: const MaterialApp(home: PlansPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(r'R$'), findsNothing);
    expect(find.textContaining('por mês'), findsNothing);
    expect(find.textContaining('Assinatura'), findsNothing);
    expect(find.text('Vários times'), findsOneWidget);
    // O teste grátis não cobra nada: continua.
    await tester.scrollUntilVisible(
      find.text('Testar grátis por 15 dias'),
      120,
    );
    expect(find.text('Testar grátis por 15 dias'), findsOneWidget);
  });
}
