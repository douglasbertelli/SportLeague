import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/games/data/presence_repository.dart';
import 'package:sport_league/features/games/domain/presence_answer.dart';
import 'package:sport_league/features/games/presentation/game_sheet_page.dart';
import 'package:sport_league/features/games/presentation/presence.dart';

import 'fake_presence.dart';

Future<void> _pump(
  WidgetTester tester,
  FakePresenceRepository repository,
  Widget child, {
  List<Athlete> athletes = const [],
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      presenceRepositoryProvider.overrideWithValue(repository),
      teamAthletesProvider.overrideWith((ref, teamId) async => athletes),
    ],
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  testWidgets('o atleta responde Sim, Não ou Talvez e pode mudar', (
    tester,
  ) async {
    final repository = FakePresenceRepository();
    var answered = 0;
    await _pump(
      tester,
      repository,
      PresenceButtons(gameId: 'g1', teamId: 't1', onAnswered: () => answered++),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sim'), findsOneWidget);
    expect(find.text('Não'), findsOneWidget);
    expect(find.text('Talvez'), findsOneWidget);

    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(repository.answers, [('g1', 't1', PresenceAnswer.yes)]);
    expect(answered, 1);
    final button = tester.widget<SegmentedButton<PresenceAnswer>>(
      find.byType(SegmentedButton<PresenceAnswer>),
    );
    expect(button.selected, {PresenceAnswer.yes});

    await tester.tap(find.text('Talvez'));
    await tester.pumpAndSettle();
    expect(repository.answers.last, ('g1', 't1', PresenceAnswer.maybe));
  });

  testWidgets('resumo das respostas e a lista com as fotos', (tester) async {
    final repository = FakePresenceRepository(
      team: const [
        (athleteId: 'a1', name: 'Bruno', answer: PresenceAnswer.yes),
        (athleteId: 'a2', name: 'Caio', answer: PresenceAnswer.yes),
        (athleteId: 'a3', name: 'Davi', answer: PresenceAnswer.no),
        (athleteId: 'a4', name: 'Enzo', answer: PresenceAnswer.maybe),
        (athleteId: 'a5', name: 'Fábio', answer: null),
      ],
    );
    await _pump(
      tester,
      repository,
      const PresenceSummary(gameId: 'g1', teamId: 't1'),
      athletes: const [
        Athlete(
          id: 'a1',
          teamId: 't1',
          name: 'Bruno Lima',
          photoUrl: 'https://example.com/bruno.png',
          profileNickname: 'Bruninho',
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Presença: 2 sim, 1 não, 1 talvez, 1 sem resposta'),
      findsOneWidget,
    );
    expect(find.text('2 de 5 confirmados'), findsOneWidget);
    expect(find.text('1 Talvez'), findsOneWidget);

    await tester.tap(find.text('Presença'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 5 confirmados'), findsNWidgets(2));
    expect(find.text('Todos (5)'), findsOneWidget);
    expect(find.text('Sem resposta (1)'), findsOneWidget);
    // Cada atleta com a foto (ou a inicial) e o apelido.
    expect(find.byType(AthleteAvatar), findsNWidgets(5));
    expect(find.text('Bruninho'), findsOneWidget);
    final photo = tester.widget<AthleteAvatar>(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Bruninho'),
        matching: find.byType(AthleteAvatar),
      ),
    );
    expect(photo.photoUrl, 'https://example.com/bruno.png');

    // O filtro mostra só uma resposta.
    await tester.ensureVisible(find.text('Talvez (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Talvez (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Enzo'), findsOneWidget);
    expect(find.text('Bruninho'), findsNothing);
    expect(find.text('Davi'), findsNothing);
  });

  testWidgets('sem pedido, o resumo não aparece', (tester) async {
    await _pump(
      tester,
      FakePresenceRepository(),
      const PresenceSummary(gameId: 'g1', teamId: 't1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Presença'), findsNothing);
  });
}
