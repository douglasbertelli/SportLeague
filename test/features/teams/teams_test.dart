import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/athletes/presentation/athletes_tab.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/presentation/game_form_page.dart';
import 'package:sport_league/features/games/presentation/games_tab.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';
import 'package:sport_league/features/teams/presentation/team_form_page.dart';

import 'fakes.dart';

Future<ProviderContainer> _container({
  required FakeTeamRepository teams,
  FakeAthleteRepository? athletes,
  FakeGameRepository? games,
  Map<String, Object> saved = const {},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      currentUserIdProvider.overrideWithValue('u1'),
      teamRepositoryProvider.overrideWithValue(teams),
      athleteRepositoryProvider.overrideWithValue(
        athletes ?? FakeAthleteRepository({}),
      ),
      gameRepositoryProvider.overrideWithValue(games ?? FakeGameRepository({})),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// App com o [page] aberto por cima de uma tela inicial, para o `pop` funcionar.
Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container,
  Widget page,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Início')),
        routes: [GoRoute(path: 'page', builder: (_, _) => page)],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
      ),
    ),
  );
  router.push('/page');
  await tester.pumpAndSettle();
}

Future<void> _pumpTab(
  WidgetTester tester,
  ProviderContainer container,
  Widget tab,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: tab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('time', () {
    test('normaliza campos opcionais ao salvar', () {
      const team = Team(
        ownerId: 'u1',
        name: '  Amigos FC ',
        city: ' ',
        state: 'sp',
        description: '',
      );
      expect(team.toMap(), {
        'owner_id': 'u1',
        'name': 'Amigos FC',
        'sport': 'football',
        'description': null,
        'city': null,
        'state': 'SP',
      });
      expect(teamB.location, 'Campinas/SP');
      expect(teamA.location, isNull);
    });

    test('time ativo: o salvo, senão o primeiro, ou nenhum', () async {
      var container = await _container(
        teams: FakeTeamRepository([teamA, teamB]),
        saved: {'selected_team_id': 'team-b'},
      );
      expect((await container.read(selectedTeamProvider.future))?.id, 'team-b');

      container = await _container(
        teams: FakeTeamRepository([teamA, teamB]),
        saved: {'selected_team_id': 'time-excluido'},
      );
      expect((await container.read(selectedTeamProvider.future))?.id, 'team-a');

      container = await _container(teams: FakeTeamRepository());
      expect(await container.read(selectedTeamProvider.future), isNull);
    });

    testWidgets('criar time salva e torna o novo time ativo', (tester) async {
      final teams = FakeTeamRepository([teamA]);
      final container = await _container(teams: teams);
      await _pumpPage(tester, container, const TeamFormPage());

      await tester.enterText(find.byType(TextFormField).first, 'Várzea United');
      await tester.tap(find.text('Criar time'));
      await tester.pumpAndSettle();

      expect(teams.created.single.name, 'Várzea United');
      expect(teams.created.single.ownerId, 'u1');
      final active = await container.read(selectedTeamProvider.future);
      expect(active?.name, 'Várzea United');
      expect(find.text('Início'), findsOneWidget);
    });
  });

  group('atletas e jogos são de cada time', () {
    testWidgets('a aba Atletas mostra só os atletas do time ativo', (
      tester,
    ) async {
      final container = await _container(
        teams: FakeTeamRepository([teamA, teamB]),
        athletes: FakeAthleteRepository({
          'team-a': [
            const Athlete(
              id: 'p1',
              teamId: 'team-a',
              name: 'Carlos Lima',
              position: 'Goleiro',
              jerseyNumber: 1,
            ),
          ],
          'team-b': [
            const Athlete(id: 'p2', teamId: 'team-b', name: 'Diego Rocha'),
          ],
        }),
      );
      await _pumpTab(tester, container, const AthletesTab());

      expect(find.text('Carlos Lima'), findsOneWidget);
      expect(find.text('Diego Rocha'), findsNothing);

      await container.read(selectedTeamIdProvider.notifier).select('team-b');
      await tester.pumpAndSettle();

      expect(find.text('Diego Rocha'), findsOneWidget);
      expect(find.text('Carlos Lima'), findsNothing);
    });

    testWidgets('sem times, as abas pedem para criar o primeiro', (
      tester,
    ) async {
      final container = await _container(teams: FakeTeamRepository());
      await _pumpTab(tester, container, const GamesTab());
      expect(find.text('Crie seu primeiro time'), findsOneWidget);

      await _pumpTab(tester, container, const AthletesTab());
      expect(find.text('Crie seu primeiro time'), findsOneWidget);
    });

    testWidgets('a aba Jogos separa próximos e anteriores do time ativo', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 22, 12);
      final container = await _container(
        teams: FakeTeamRepository([teamA, teamB]),
        games: FakeGameRepository({
          'team-a': [
            Game(
              id: 'g1',
              teamId: 'team-a',
              opponent: 'Unidos da Vila',
              scheduledAt: DateTime(2026, 10, 18, 15),
              teamScore: 3,
              opponentScore: 1,
            ),
            Game(
              id: 'g2',
              teamId: 'team-a',
              opponent: 'Real Bairro',
              scheduledAt: DateTime(2026, 10, 25, 15),
              type: GameType.championship,
            ),
          ],
          'team-b': [
            Game(
              id: 'g3',
              teamId: 'team-b',
              opponent: 'Outro Time',
              scheduledAt: DateTime(2026, 10, 26, 15),
            ),
          ],
        }),
      );
      await _pumpTab(tester, container, GamesTab(now: now));

      expect(find.text('Próximos'), findsOneWidget);
      expect(find.text('Anteriores'), findsOneWidget);
      expect(find.text('x Real Bairro'), findsOneWidget);
      expect(find.text('Campeonato'), findsOneWidget);
      expect(find.text('x Unidos da Vila'), findsOneWidget);
      expect(find.text('Vitória 3 x 1'), findsOneWidget);
      expect(find.text('x Outro Time'), findsNothing);
      expect(
        tester.getTopLeft(find.text('x Real Bairro')).dy,
        lessThan(tester.getTopLeft(find.text('x Unidos da Vila')).dy),
      );
    });

    testWidgets('marcar jogo exige data e placar completo', (tester) async {
      final games = FakeGameRepository({});
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        games: games,
      );
      await _pumpPage(tester, container, const GameFormPage());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Adversário').first,
        'Real Bairro',
      );
      final scoreFields = find.byType(TextFormField);
      await tester.enterText(scoreFields.at(2), '2');

      final submit = find.text('Marcar jogo');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(find.text('Escolha a data e a hora'), findsOneWidget);
      expect(find.text('Preencha os dois placares'), findsNWidgets(2));
      expect(games.created, isEmpty);
    });
  });

  group('jogo', () {
    test('resultado e envio da data em UTC', () {
      final date = DateTime(2026, 10, 25, 15);
      Game game({int? team, int? opponent}) => Game(
        teamId: 'team-a',
        opponent: 'Real Bairro',
        scheduledAt: date,
        teamScore: team,
        opponentScore: opponent,
      );

      expect(game().resultLabel, isNull);
      expect(game(team: 2, opponent: 2).resultLabel, 'Empate 2 x 2');
      expect(game(team: 0, opponent: 1).resultLabel, 'Derrota 0 x 1');
      expect(game().toMap()['scheduled_at'], date.toUtc().toIso8601String());
    });
  });
}
