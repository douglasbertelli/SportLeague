import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/fundraisers/data/fundraiser_repository.dart';
import 'package:sport_league/features/fundraisers/domain/fundraiser.dart';
import 'package:sport_league/features/fundraisers/presentation/fundraiser_form_page.dart';
import 'package:sport_league/features/fundraisers/presentation/fundraiser_page.dart';
import 'package:sport_league/features/home/presentation/app_drawer.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:sport_league/features/teams/domain/team.dart';

import '../teams/fakes.dart';

class FakeFundraiserRepository implements FundraiserRepository {
  final fundraisers = <Fundraiser>[];
  final payments = <String, Set<String>>{};

  @override
  Future<List<Fundraiser>> fetchTeam(String teamId) async => [
    for (final fundraiser in fundraisers)
      if (fundraiser.teamId == teamId) fundraiser,
  ];

  @override
  Future<Fundraiser> create(Fundraiser fundraiser) async {
    final created = Fundraiser(
      id: 'f${fundraisers.length + 1}',
      teamId: fundraiser.teamId,
      item: fundraiser.item,
      description: fundraiser.description,
      amountCents: fundraiser.amountCents,
      amountType: fundraiser.amountType,
    );
    fundraisers.add(created);
    return created;
  }

  @override
  Future<void> update(Fundraiser fundraiser) async {
    final index = fundraisers.indexWhere((f) => f.id == fundraiser.id);
    fundraisers[index] = fundraiser;
  }

  @override
  Future<void> delete(String fundraiserId) async =>
      fundraisers.removeWhere((f) => f.id == fundraiserId);

  @override
  Future<FundraiserPayments> fetchPayments(String fundraiserId) async => {
    ...?payments[fundraiserId],
  };

  @override
  Future<void> setPaid(
    String fundraiserId,
    FundraiserParticipant participant, {
    required bool paid,
  }) async {
    final paidKeys = payments.putIfAbsent(fundraiserId, () => {});
    paid ? paidKeys.add(participant.key) : paidKeys.remove(participant.key);
  }

  @override
  Future<({String name, String? photoUrl})> fetchOwner(String ownerId) async =>
      (name: 'Douglas Admin', photoUrl: null);
}

const _team = Team(
  id: 'team-a',
  ownerId: 'u1',
  name: 'Amigos FC',
  modalities: {Modality.society},
);

final _athletes = FakeAthleteRepository({
  'team-a': const [
    Athlete(id: 'a1', teamId: 'team-a', name: 'Bruno Lima', jerseyNumber: 9),
    Athlete(id: 'a2', teamId: 'team-a', name: 'Caio Souza', jerseyNumber: 10),
  ],
});

const _ball = Fundraiser(
  id: 'f1',
  teamId: 'team-a',
  item: FundraiserItem.ball,
  amountCents: 2500,
);

Future<void> _pump(
  WidgetTester tester,
  FakeFundraiserRepository fundraisers,
  Widget page, {
  String userId = 'u1',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Início')),
        routes: [GoRoute(path: 'page', builder: (_, _) => page)],
      ),
      GoRoute(
        path: Routes.fundraiserForm,
        builder: (_, state) {
          final (:team, :fundraiser) = state.extra as FundraiserArgs;
          return FundraiserFormPage(team: team, fundraiser: fundraiser);
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(userId),
        fundraiserRepositoryProvider.overrideWithValue(fundraisers),
        athleteRepositoryProvider.overrideWithValue(_athletes),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push('/page');
  await tester.pumpAndSettle();
}

void main() {
  test('valor em reais', () {
    expect(parseMoney('25'), 2500);
    expect(parseMoney('25,5'), 2550);
    expect(parseMoney('1.250,00'), 125000);
    expect(parseMoney(r'R$ 12,90'), 1290);
    expect(parseMoney('12.9'), 1290);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney(''), isNull);
    expect(formatMoney(2500).replaceAll(' ', ' '), r'R$ 25,00');
  });

  testWidgets('em "Outros" o administrador diz o que vai comprar', (
    tester,
  ) async {
    final fundraisers = FakeFundraiserRepository();
    await _pump(tester, fundraisers, const FundraiserFormPage(team: _team));

    expect(find.text('O que vai ser comprado?'), findsNothing);
    await tester.tap(find.text('Outros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar vaquinha'));
    await tester.pumpAndSettle();
    expect(find.text('Informe o que vai ser comprado'), findsOneWidget);
    expect(find.text('Informe o valor'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'O que vai ser comprado?'),
      'Rede do gol',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Valor por pessoa'),
      '15,50',
    );
    await tester.tap(find.text('Criar vaquinha'));
    await tester.pumpAndSettle();

    final created = fundraisers.fundraisers.single;
    expect(created.item, FundraiserItem.other);
    expect(created.title, 'Rede do gol');
    expect(created.amountCents, 1550);
    expect(find.text('Início'), findsOneWidget);
  });

  test('valor total dividido entre as pessoas', () {
    const shirts = Fundraiser(
      teamId: 'team-a',
      item: FundraiserItem.kit,
      amountCents: 10000,
      amountType: AmountType.total,
    );
    // R$ 100,00 por 3: R$ 33,34 cada (o centavo arredonda para cima).
    expect(shirts.shareCents(3), 3334);
    expect(shirts.goalCents(3), 10000);
    expect(_ball.shareCents(3), 2500);
    expect(_ball.goalCents(3), 7500);
  });

  testWidgets('valor total do produto: o formulário mostra a divisão', (
    tester,
  ) async {
    final fundraisers = FakeFundraiserRepository();
    await _pump(tester, fundraisers, const FundraiserFormPage(team: _team));

    await tester.tap(find.text('Valor total'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Valor total do produto'),
      '90',
    );
    await tester.pump();
    // Administrador + 2 atletas.
    expect(
      find.textContaining('Dividido por 3 pessoas: ${formatMoney(3000)}'),
      findsOneWidget,
    );

    await tester.tap(find.text('Criar vaquinha'));
    await tester.pumpAndSettle();
    final created = fundraisers.fundraisers.single;
    expect(created.amountType, AmountType.total);
    expect(created.amountCents, 9000);
  });

  testWidgets('vaquinha de valor total mostra quanto cada um paga', (
    tester,
  ) async {
    const kit = Fundraiser(
      id: 'f2',
      teamId: 'team-a',
      item: FundraiserItem.kit,
      amountCents: 9000,
      amountType: AmountType.total,
    );
    final fundraisers = FakeFundraiserRepository()
      ..fundraisers.add(kit)
      ..payments['f2'] = {'a1'};
    await _pump(
      tester,
      fundraisers,
      const FundraiserPage(team: _team, fundraiser: kit),
    );
    expect(find.text('${formatMoney(3000)} por pessoa'), findsOneWidget);
    expect(find.textContaining('dividido por 3 pessoas'), findsOneWidget);
    expect(find.text(formatMoney(3000)), findsOneWidget);
    expect(
      find.textContaining('de ${formatMoney(9000)} · 1 de 3 pagaram'),
      findsOneWidget,
    );
  });

  testWidgets('o administrador marca quem pagou e vê o total', (tester) async {
    final fundraisers = FakeFundraiserRepository()..fundraisers.add(_ball);
    await _pump(
      tester,
      fundraisers,
      const FundraiserPage(team: _team, fundraiser: _ball),
    );

    // Administrador e os dois atletas, ninguém pagou.
    expect(find.text('Douglas Admin'), findsOneWidget);
    expect(find.text('Bruno Lima'), findsOneWidget);
    expect(find.text('Caio Souza'), findsOneWidget);
    expect(find.text('Não'), findsNWidgets(3));
    expect(find.textContaining('0 de 3 pagaram'), findsOneWidget);

    await tester.tap(find.text('Bruno Lima'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Douglas Admin'));
    await tester.pumpAndSettle();

    expect(fundraisers.payments['f1'], {'a1', 'profile:u1'});
    expect(find.text('Sim'), findsNWidgets(2));
    expect(find.textContaining('2 de 3 pagaram'), findsOneWidget);
    expect(
      find.text(formatMoney(5000)),
      findsOneWidget,
      reason: 'total arrecadado: 2 x R\$ 25,00',
    );
  });

  testWidgets('o atleta só acompanha', (tester) async {
    final fundraisers = FakeFundraiserRepository()
      ..fundraisers.add(_ball)
      ..payments['f1'] = {'a2'};
    await _pump(
      tester,
      fundraisers,
      const FundraiserPage(team: _team, fundraiser: _ball),
      userId: 'u9',
    );

    expect(find.byType(Switch), findsNothing);
    expect(find.byTooltip('Ações da vaquinha'), findsNothing);
    expect(find.text('Sim'), findsOneWidget);
    expect(find.text('Não'), findsNWidgets(2));

    await tester.tap(find.text('Bruno Lima'));
    await tester.pumpAndSettle();
    expect(fundraisers.payments['f1'], {'a2'});
  });

  testWidgets('o menu lateral abre a vaquinha', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            appBar: AppBar(actions: const [AppDrawerButton()]),
            endDrawer: const AppDrawer(
              profile: Profile(
                id: 'u1',
                fullName: 'Douglas Admin',
                role: UserRole.admin,
                plan: SubscriptionPlan.free,
              ),
            ),
            body: const SizedBox.shrink(),
          ),
        ),
        GoRoute(
          path: Routes.fundraisers,
          builder: (_, _) => const Scaffold(body: Text('Tela da vaquinha')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Douglas Admin'), findsOneWidget);
    await tester.tap(find.text('Vaquinha'));
    await tester.pumpAndSettle();
    expect(find.text('Tela da vaquinha'), findsOneWidget);
  });

  testWidgets('vaquinha encerrada não muda os pagamentos', (tester) async {
    final closed = _ball.copyWith(closed: true);
    final fundraisers = FakeFundraiserRepository()..fundraisers.add(closed);
    await _pump(
      tester,
      fundraisers,
      FundraiserPage(team: _team, fundraiser: closed),
    );
    expect(find.text('Encerrada'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);

    // O administrador reabre pelo menu.
    await tester.tap(find.byTooltip('Ações da vaquinha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reabrir'));
    await tester.pumpAndSettle();
    expect(fundraisers.fundraisers.single.closed, isFalse);
    expect(find.byType(Switch), findsNWidgets(3));
  });
}
