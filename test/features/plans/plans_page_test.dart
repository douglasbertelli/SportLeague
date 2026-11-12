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
}
