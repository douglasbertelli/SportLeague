import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/media/picked_image.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/athletes/presentation/athlete_form_page.dart';
import 'package:sport_league/features/athletes/presentation/athletes_tab.dart';
import 'package:sport_league/features/availability/data/availability_repository.dart';
import 'package:sport_league/features/availability/domain/availability.dart';
import 'package:sport_league/features/availability/presentation/availability_page.dart';
import 'package:sport_league/features/availability/presentation/slot_picker_page.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/core/theme/app_theme.dart';
import 'package:sport_league/features/games/data/opponent_repository.dart';
import 'package:sport_league/features/games/domain/opponent.dart';
import 'package:sport_league/features/games/presentation/game_card.dart';
import 'package:sport_league/features/games/presentation/game_form_page.dart';
import 'package:sport_league/features/games/presentation/opponent_picker_page.dart';
import 'package:sport_league/features/games/presentation/games_tab.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';
import 'package:sport_league/features/teams/presentation/team_form_page.dart';
import 'package:sport_league/features/venues/data/venue_repository.dart';
import 'package:sport_league/features/venues/presentation/venue_form_page.dart';
import 'package:sport_league/features/venues/presentation/venues_page.dart';

import 'fakes.dart';

/// PNG 1x1 transparente, para o preview do logo no formulário.
const _transparentPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

Future<ProviderContainer> _container({
  required FakeTeamRepository teams,
  FakeAthleteRepository? athletes,
  FakeGameRepository? games,
  FakeOpponentRepository? opponents,
  FakeAvailabilityRepository? availability,
  FakeVenueRepository? venues,
  PickImage? pickImage,
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
      opponentRepositoryProvider.overrideWithValue(
        opponents ?? FakeOpponentRepository(),
      ),
      availabilityRepositoryProvider.overrideWithValue(
        availability ?? FakeAvailabilityRepository(),
      ),
      venueRepositoryProvider.overrideWithValue(
        venues ?? FakeVenueRepository(),
      ),
      if (pickImage != null) pickImageProvider.overrideWithValue(pickImage),
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
      GoRoute(
        path: Routes.pickOpponent,
        builder: (_, state) {
          final (:teamId, :modalities, :modality) =
              state.extra as OpponentPickerArgs;
          return OpponentPickerPage(
            teamId: teamId,
            modalities: modalities,
            modality: modality,
          );
        },
      ),
      GoRoute(
        path: Routes.pickVenue,
        builder: (_, _) => const VenuesPage(picking: true),
      ),
      GoRoute(
        path: Routes.newVenue,
        builder: (_, state) =>
            VenueFormPage(initialName: state.extra as String?),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
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
        theme: AppTheme.dark(),
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
  setUpAll(() => initializeDateFormatting('pt_BR'));

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
        'modalities': <String>[],
        'gender': null,
        'age_group': 'open',
        'founded_on': null,
        'logo_url': null,
        'description': null,
        'city': null,
        'state': 'SP',
      });
      expect(teamB.location, 'Campinas/SP');
      expect(teamA.location, isNull);
    });

    test('modalidade, gênero, faixa de idade e fundação vão e voltam', () {
      final team = Team.fromMap({
        'id': 't1',
        'owner_id': 'u1',
        'name': 'Areia FC',
        'sport': 'football',
        'modalities': ['beach', 'futsal'],
        'gender': 'female',
        'age_group': 'master',
        'founded_on': '2015-03-08',
        'logo_url': 'https://storage.test/logo',
      });

      expect(team.modalities, {Modality.futsal, Modality.beach});
      expect(team.gender, TeamGender.female);
      expect(team.ageGroup, AgeGroup.master);
      expect(team.foundedOn, DateTime(2015, 3, 8));
      expect(team.summary, 'Futsal, Futebol de Areia · Feminino · Master');
      expect(team.toMap()['modalities'], ['futsal', 'beach']);
      expect(team.toMap()['founded_on'], '2015-03-08');

      // Times criados antes destes campos.
      final old = Team.fromMap({
        'id': 't2',
        'owner_id': 'u1',
        'name': 'Antigo FC',
        'sport': 'football',
      });
      expect(old.modalities, isEmpty);
      expect(old.gender, isNull);
      expect(old.ageGroup, AgeGroup.open);
      expect(old.summary, 'Livre');
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

    Future<void> tapCreate(WidgetTester tester) async {
      final submit = find.text('Criar time');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
    }

    Future<void> tapVisible(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('criar time exige modalidade e gênero', (tester) async {
      final teams = FakeTeamRepository([teamA]);
      final container = await _container(teams: teams);
      await _pumpPage(tester, container, const TeamFormPage());

      await tester.enterText(find.byType(TextFormField).first, 'Várzea United');
      await tapCreate(tester);

      expect(find.text('Escolha pelo menos uma modalidade'), findsOneWidget);
      expect(find.text('Escolha o gênero'), findsOneWidget);
      expect(teams.created, isEmpty);
    });

    testWidgets('criar time salva os detalhes, o logo e o torna ativo', (
      tester,
    ) async {
      final teams = FakeTeamRepository([teamA]);
      final logo = PickedImage(
        bytes: Uint8List.fromList(_transparentPng),
        contentType: 'image/png',
      );
      final container = await _container(
        teams: teams,
        pickImage: (source) async => logo,
      );
      await _pumpPage(tester, container, const TeamFormPage());

      await tester.tap(find.bySemanticsLabel('Adicionar logo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escolher da galeria'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Várzea United');
      await tapVisible(tester, 'Society');
      await tapVisible(tester, 'Campo');
      await tapVisible(tester, 'Feminino');
      await tapVisible(tester, 'Base');
      expect(find.text('4 a 20 anos'), findsOneWidget);
      await tapCreate(tester);

      final created = teams.created.single;
      expect(created.name, 'Várzea United');
      expect(created.ownerId, 'u1');
      expect(created.modalities, {Modality.society, Modality.field});
      expect(created.gender, TeamGender.female);
      expect(created.ageGroup, AgeGroup.youth);
      expect(created.logoUrl, isNull);

      // Depois de criado, o logo é enviado e a URL gravada no time.
      final active = await container.read(selectedTeamProvider.future);
      expect(active?.name, 'Várzea United');
      expect(teams.uploadedLogos[active!.id], same(logo));
      expect(
        teams.updated.last.logoUrl,
        'https://storage.test/team-logos/u1/${active.id}',
      );
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

    testWidgets('a aba Jogos divide o time ativo em Marcados, Pendentes, '
        'Cancelados e Realizados', (tester) async {
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
              modality: Modality.society,
            ),
            Game(
              id: 'g4',
              teamId: 'team-a',
              opponent: 'Vila Nova',
              opponentTeamId: 'team-vila',
              status: GameStatus.pending,
              scheduledAt: DateTime(2026, 10, 30, 15),
            ),
            Game(
              id: 'g5',
              teamId: 'team-a',
              opponent: 'Desistentes FC',
              opponentTeamId: 'team-desist',
              status: GameStatus.canceled,
              canceledByTeamId: 'team-desist',
              scheduledAt: DateTime(2026, 10, 28, 15),
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

      // As abas rolam na horizontal quando não cabem.
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.isScrollable, isTrue);
      for (final label in [
        'Marcados (1)',
        'Pendentes (1)',
        'Cancelados (1)',
        'Realizados (1)',
      ]) {
        expect(find.text(label), findsOneWidget);
      }

      // Card: time ativo à esquerda (sigla), adversário à direita, mando.
      expect(find.bySemanticsLabel('Amigos FC'), findsOneWidget);
      expect(find.bySemanticsLabel('Real Bairro'), findsOneWidget);
      expect(find.text('AMI'), findsOneWidget);
      expect(find.text('REA'), findsOneWidget);
      expect(find.text('25/10/2026'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('Mandante'), findsOneWidget);
      expect(find.text('Society'), findsOneWidget);
      expect(find.bySemanticsLabel('Outro Time'), findsNothing);

      await tester.tap(find.text('Pendentes (1)'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Vila Nova'), findsOneWidget);
      expect(
        find.textContaining('Aguardando Vila Nova aceitar'),
        findsOneWidget,
      );
      // Quem marcou não aceita o próprio amistoso: edita ou cancela.
      await tester.tap(find.byTooltip('Ações do amistoso'));
      await tester.pumpAndSettle();
      expect(find.text('Aceitar'), findsNothing);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Cancelar amistoso'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelados (1)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cancelado por Desistentes FC'),
        findsOneWidget,
      );

      await tester.tap(find.text('Realizados (1)'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Unidos da Vila'), findsOneWidget);
      // Com placar, o "×" do cabeçalho vira o resultado.
      expect(find.text('3 × 1'), findsOneWidget);
    });

    testWidgets('o adversário aceita ou recusa o amistoso pendente', (
      tester,
    ) async {
      const rivalTeam = Team(
        id: 'team-rival',
        ownerId: 'u1',
        name: 'Real Bairro',
        modalities: {Modality.society},
      );
      Game invite(String id) => Game(
        id: id,
        teamId: 'team-a',
        hostTeamName: 'Amigos FC',
        opponent: 'Real Bairro',
        opponentTeamId: 'team-rival',
        status: GameStatus.pending,
        modality: Modality.society,
        scheduledAt: DateTime(2026, 10, 25, 15),
      );
      final games = FakeGameRepository({
        'team-a': [invite('g1'), invite('g2')],
      });
      final container = await _container(
        teams: FakeTeamRepository([rivalTeam]),
        games: games,
      );
      await _pumpTab(
        tester,
        container,
        GamesTab(now: DateTime(2026, 10, 22, 12)),
      );

      await tester.tap(find.text('Pendentes (2)'));
      await tester.pumpAndSettle();
      // Aceitar e Recusar ficam à vista no card, sem menu.
      expect(find.textContaining('Aguardando sua resposta'), findsNothing);
      expect(find.byTooltip('Ações do amistoso'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Aceitar'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, 'Recusar'), findsNWidgets(2));

      expect(find.text('Visitante'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FilledButton, 'Aceitar').first);
      await tester.pumpAndSettle();
      expect(games.accepted, ['g1']);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Recusar').last);
      await tester.pumpAndSettle();
      expect(find.text('Recusar amistoso?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Recusar'));
      await tester.pumpAndSettle();
      expect(games.canceled, ['g2']);
    });

    testWidgets('o adversário pode cancelar um amistoso marcado', (
      tester,
    ) async {
      const rivalTeam = Team(
        id: 'team-rival',
        ownerId: 'u1',
        name: 'Real Bairro',
        modalities: {Modality.society},
      );
      final games = FakeGameRepository({
        'team-a': [
          Game(
            id: 'g1',
            teamId: 'team-a',
            hostTeamName: 'Amigos FC',
            opponent: 'Real Bairro',
            opponentTeamId: 'team-rival',
            // Quem marcou joga como visitante: o adversário é o mandante.
            hostIsHome: false,
            modality: Modality.society,
            scheduledAt: DateTime(2026, 10, 25, 15),
          ),
        ],
      });
      final container = await _container(
        teams: FakeTeamRepository([rivalTeam]),
        games: games,
      );
      await _pumpTab(
        tester,
        container,
        GamesTab(now: DateTime(2026, 10, 22, 12)),
      );

      expect(find.bySemanticsLabel('Amigos FC'), findsOneWidget);
      expect(find.text('Mandante'), findsOneWidget);
      await tester.tap(find.byTooltip('Ações do amistoso'));
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsNothing);
      await tester.tap(find.text('Cancelar amistoso'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar amistoso'));
      await tester.pumpAndSettle();
      expect(games.canceled, ['g1']);
    });
  });

  group('amistoso', () {
    const rival = Team(
      id: 'team-rival',
      ownerId: 'u2',
      name: 'Real Bairro',
      modalities: {Modality.society},
    );
    const guest = GuestTeam(
      id: 'guest-1',
      ownerId: 'u1',
      name: 'Pelada de Sábado',
      modality: Modality.society,
    );

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    final opponentField = find.widgetWithText(InputDecorator, 'Adversário');

    testWidgets(
      'sem tipo, placar, time e modalidade; exige adversário e data',
      (tester) async {
        final games = FakeGameRepository({});
        final container = await _container(
          teams: FakeTeamRepository([teamA]),
          games: games,
        );
        await _pumpPage(tester, container, const GameFormPage());

        expect(find.text('Amistoso'), findsNothing);
        expect(find.text('Campeonato'), findsNothing);
        expect(find.textContaining('Placar'), findsNothing);
        expect(find.textContaining('Time: '), findsNothing);
        expect(find.text('Modalidade'), findsNothing);
        expect(find.text('Society'), findsNothing);

        await tapVisible(tester, find.text('Marcar amistoso'));

        expect(find.text('Escolha o adversário'), findsOneWidget);
        expect(find.text('Escolha a data e a hora'), findsOneWidget);
        expect(find.text('Escolha o local'), findsOneWidget);
        expect(games.created, isEmpty);
      },
    );

    testWidgets('pesquisa só a modalidade escolhida e salva o adversário', (
      tester,
    ) async {
      final games = FakeGameRepository({});
      final opponents = FakeOpponentRepository(
        registered: [rival],
        guests: [guest],
      );
      final soon = DateTime.now().add(const Duration(days: 3));
      final rivalSlot = DateTime(soon.year, soon.month, soon.day, 15);
      final availability = FakeAvailabilityRepository(
        freeByTeam: {
          'team-rival': [rivalSlot],
        },
      );
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        games: games,
        opponents: opponents,
        availability: availability,
        venues: FakeVenueRepository([arena]),
      );
      final game = Game(
        id: 'g1',
        teamId: 'team-a',
        opponent: 'Antigo FC',
        scheduledAt: DateTime(2026, 10, 25, 15),
        location: 'Campo do Zé',
      );
      await _pumpPage(tester, container, GameFormPage(game: game));

      // A modalidade é escolhida na pesquisa do adversário.
      await tapVisible(tester, opponentField);
      expect(find.text('Escolher adversário'), findsOneWidget);
      expect(find.text('Modalidade'), findsOneWidget);
      await tapVisible(tester, find.text('Campo'));
      expect(opponents.searches.last.modality, Modality.field);
      expect(find.text('Real Bairro'), findsNothing);
      await tapVisible(tester, find.text('Society'));
      expect(opponents.searches.last.modality, Modality.society);
      expect(opponents.searches.last.teamId, 'team-a');

      await tester.enterText(find.byType(TextField), 'real');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(opponents.searches.last.query, 'real');

      await tapVisible(tester, find.text('Real Bairro'));
      expect(find.text('Real Bairro'), findsOneWidget);

      // Jogar como: mandante por padrão; escolhe visitante.
      expect(find.text('Jogar como'), findsOneWidget);
      await tapVisible(tester, find.text('Visitante'));

      // O adversário mudou: a data antiga sai e o horário vem do calendário
      // do Real Bairro.
      expect(find.text('Escolha a data e a hora'), findsNothing);
      expect(
        find.text('Horários livres no calendário do Real Bairro'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Data e hora'));
      expect(find.text('Escolher dia e horário'), findsOneWidget);
      expect(availability.freeSlotRequests.last, 'team-rival');
      await tapVisible(tester, find.text('15:00'));

      // Jogo antigo: mostra o local digitado antes e pede um cadastrado.
      expect(find.text('Antes: Campo do Zé'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(InputDecorator, 'Local'));
      expect(find.text('Escolher local'), findsOneWidget);
      await tapVisible(tester, find.text('Arena Society Central'));
      expect(find.text('Arena Society Central'), findsOneWidget);
      expect(find.text(arena.address), findsOneWidget);

      await tapVisible(tester, find.text('Salvar'));
      final saved = games.updated.single;
      expect(saved.venueId, 'venue-1');
      expect(saved.toMap()['venue_id'], 'venue-1');
      expect(saved.toMap()['location'], isNull);
      expect(saved.opponent, 'Real Bairro');
      expect(saved.opponentTeamId, 'team-rival');
      expect(saved.opponentGuestId, isNull);
      expect(saved.modality, Modality.society);
      expect(saved.scheduledAt, rivalSlot);
      expect(saved.hostIsHome, isFalse);
      expect(saved.toMap()['host_is_home'], isFalse);
      expect(saved.toMap().containsKey('team_score'), isFalse);
      expect(saved.toMap().containsKey('type'), isFalse);
    });

    testWidgets('cria time fictício quando o adversário não existe', (
      tester,
    ) async {
      final opponents = FakeOpponentRepository();
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        opponents: opponents,
      );
      await _pumpPage(tester, container, const GameFormPage());

      await tapVisible(tester, opponentField);
      await tapVisible(tester, find.text('Campo'));
      expect(find.text('Nenhum time encontrado.'), findsOneWidget);

      await tapVisible(tester, find.text('Criar time fictício'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome do time'),
        'Várzea da Esquina',
      );
      await tapVisible(tester, find.text('Criar'));

      final created = opponents.createdGuests.single;
      expect(created.name, 'Várzea da Esquina');
      expect(created.ownerId, 'u1');
      expect(created.modality, Modality.field);
      expect(find.text('Várzea da Esquina (fictício)'), findsOneWidget);
    });

    testWidgets('time de uma modalidade não escolhe modalidade', (
      tester,
    ) async {
      final opponents = FakeOpponentRepository(registered: [rival]);
      final container = await _container(
        teams: FakeTeamRepository([teamB]),
        opponents: opponents,
      );
      await _pumpPage(tester, container, const GameFormPage());

      await tapVisible(tester, opponentField);
      expect(find.text('Escolher adversário'), findsOneWidget);
      expect(find.text('Modalidade'), findsNothing);
      expect(opponents.searches.last.modality, Modality.society);
      await tapVisible(tester, find.text('Real Bairro'));
      expect(find.text('Real Bairro'), findsOneWidget);
    });
  });

  group('foto do atleta', () {
    Future<void> tapSave(WidgetTester tester) async {
      final submit = find.text('Cadastrar atleta');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
    }

    testWidgets('cadastrar atleta exige a foto', (tester) async {
      final athletes = FakeAthleteRepository({});
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        athletes: athletes,
      );
      await _pumpPage(tester, container, const AthleteFormPage());

      await tester.enterText(find.byType(TextFormField).first, 'Carlos Lima');
      await tapSave(tester);

      expect(find.text('Adicione a foto do atleta'), findsOneWidget);
      expect(athletes.created, isEmpty);
    });

    testWidgets('cadastrar atleta envia a foto e grava o caminho', (
      tester,
    ) async {
      final athletes = FakeAthleteRepository({});
      final photo = PickedImage(
        bytes: Uint8List.fromList(_transparentPng),
        contentType: 'image/png',
      );
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        athletes: athletes,
        pickImage: (source) async => photo,
      );
      await _pumpPage(tester, container, const AthleteFormPage());

      await tester.tap(find.bySemanticsLabel('Adicionar foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tirar foto'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Trocar foto'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Carlos Lima');
      await tapSave(tester);

      expect(athletes.created.single.name, 'Carlos Lima');
      expect(athletes.created.single.teamId, 'team-a');
      expect(athletes.uploadedPhotos['athlete-1'], same(photo));
      // Pasta do dono do time, depois o time e o atleta.
      expect(athletes.updated.last.photoPath, 'u1/team-a/athlete-1');
      expect(find.text('Início'), findsOneWidget);
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

      expect(game().resultLabelFor('team-a'), isNull);
      expect(
        game(team: 2, opponent: 2).resultLabelFor('team-a'),
        'Empate 2 x 2',
      );
      expect(
        game(team: 0, opponent: 1).resultLabelFor('team-a'),
        'Derrota 0 x 1',
      );
      // Do lado do adversário, o placar se inverte.
      expect(
        game(team: 0, opponent: 1).resultLabelFor('team-rival'),
        'Vitória 1 x 0',
      );
      expect(game().toMap()['scheduled_at'], date.toUtc().toIso8601String());
    });

    test('mando: quem marcou escolhe e o adversário fica com o oposto', () {
      Game game({required bool hostIsHome}) => Game(
        teamId: 'team-a',
        opponent: 'Real Bairro',
        opponentTeamId: 'team-rival',
        hostIsHome: hostIsHome,
        scheduledAt: DateTime(2026, 10, 25),
      );

      expect(game(hostIsHome: true).isHomeFor('team-a'), isTrue);
      expect(game(hostIsHome: true).isHomeFor('team-rival'), isFalse);
      expect(game(hostIsHome: false).isHomeFor('team-a'), isFalse);
      expect(game(hostIsHome: false).isHomeFor('team-rival'), isTrue);
      // Jogos antigos, sem o campo, ficam com quem marcou como mandante.
      final old = Game.fromMap({
        'id': 'g1',
        'team_id': 'team-a',
        'opponent': 'Real Bairro',
        'scheduled_at': '2026-10-25T18:00:00Z',
      });
      expect(old.hostIsHome, isTrue);
    });

    test('quem marcou e o adversário veem o outro time', () {
      final game = Game.fromMap({
        'id': 'g1',
        'team_id': 'team-a',
        'opponent': 'Real Bairro',
        'opponent_team_id': 'team-rival',
        'scheduled_at': '2026-10-25T18:00:00Z',
        'modality': 'society',
        'host': {'name': 'Amigos FC'},
      });

      expect(game.isHostedBy('team-a'), isTrue);
      expect(game.opponentNameFor('team-a'), 'Real Bairro');
      expect(game.isHostedBy('team-rival'), isFalse);
      expect(game.opponentNameFor('team-rival'), 'Amigos FC');
      expect(game.toMap().containsKey('host'), isFalse);
    });

    test('aba de cada situação; a situação não é enviada pelo formulário', () {
      final now = DateTime(2026, 10, 22, 12);
      Game game(GameStatus status, DateTime date) => Game(
        teamId: 'team-a',
        opponent: 'Real Bairro',
        status: status,
        scheduledAt: date,
      );
      final future = DateTime(2026, 10, 25);
      final past = DateTime(2026, 10, 18);

      expect(
        game(GameStatus.scheduled, future).stageAt(now),
        GameStage.scheduled,
      );
      expect(game(GameStatus.scheduled, past).stageAt(now), GameStage.played);
      expect(game(GameStatus.pending, past).stageAt(now), GameStage.pending);
      expect(
        game(GameStatus.canceled, future).stageAt(now),
        GameStage.canceled,
      );
      expect(
        game(GameStatus.pending, future).toMap().containsKey('status'),
        isFalse,
      );
      expect(GameStage.values.map((s) => s.label), [
        'Marcados',
        'Pendentes',
        'Cancelados',
        'Realizados',
      ]);
    });
  });

  testWidgets('amistoso marcado por outro time aparece para o adversário', (
    tester,
  ) async {
    const rivalTeam = Team(
      id: 'team-rival',
      ownerId: 'u1',
      name: 'Real Bairro',
      modalities: {Modality.society},
    );
    final hosted = Game(
      id: 'g1',
      teamId: 'team-a',
      hostTeamName: 'Amigos FC',
      opponent: 'Real Bairro',
      opponentTeamId: 'team-rival',
      modality: Modality.society,
      scheduledAt: DateTime(2026, 10, 18, 15),
      teamScore: 0,
      opponentScore: 2,
    );
    final container = await _container(
      teams: FakeTeamRepository([rivalTeam]),
      games: FakeGameRepository({
        'team-a': [hosted],
      }),
    );
    await _pumpTab(
      tester,
      container,
      GamesTab(now: DateTime(2026, 10, 22, 12)),
    );

    // A data já passou: está em Realizados.
    await tester.tap(find.text('Realizados (1)'));
    await tester.pumpAndSettle();
    // Do lado do adversário: o time ativo à esquerda e quem marcou à direita.
    expect(find.bySemanticsLabel('Real Bairro'), findsOneWidget);
    expect(find.bySemanticsLabel('Amigos FC'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('REA')).dx,
      lessThan(tester.getTopLeft(find.text('AMI')).dx),
    );
    expect(find.text('Visitante'), findsOneWidget);
    // Placar invertido para o adversário.
    expect(find.text('2 × 0'), findsOneWidget);
    // Jogo realizado: o adversário não tem ações.
    expect(find.byTooltip('Ações do amistoso'), findsNothing);
  });

  test('sigla do time e formato de data e hora do card', () {
    expect(teamCode('Barcelona'), 'BAR');
    expect(teamCode('Bayern de Munique'), 'BAY');
    expect(teamCode('São Paulo'), 'SÃO');
    expect(teamCode('A1'), 'A1');
    expect(formatGameDay(DateTime(2026, 3, 12, 20)), '12/03/2026');
    expect(formatGameTime(DateTime(2026, 3, 12, 20)), '20:00');
    expect(formatGameTime(DateTime(2026, 3, 12, 9, 5)), '09:05');
  });

  group('disponibilidade', () {
    test('avulso, recorrente e recorrente a partir de uma data', () {
      final single = Availability.single(
        teamId: 'team-a',
        startsAt: DateTime(2026, 10, 25, 15),
      );
      const weekly = Availability.weekly(
        teamId: 'team-a',
        weekday: DateTime.saturday,
        startTime: TimeOfDay(hour: 9, minute: 30),
      );
      final fromNovember = Availability.weekly(
        teamId: 'team-a',
        weekday: DateTime.saturday,
        startTime: const TimeOfDay(hour: 9, minute: 30),
        startsOn: DateTime(2026, 11, 1),
      );

      expect(single.occursOn(DateTime(2026, 10, 25)), isTrue);
      expect(single.occursOn(DateTime(2026, 11, 1)), isFalse);
      expect(weekly.occursOn(DateTime(2026, 10, 24)), isTrue); // sábado
      expect(weekly.occursOn(DateTime(2026, 10, 25)), isFalse); // domingo
      expect(weekly.at(DateTime(2026, 10, 24)), DateTime(2026, 10, 24, 9, 30));
      expect(fromNovember.occursOn(DateTime(2026, 10, 31)), isFalse);
      expect(fromNovember.occursOn(DateTime(2026, 11, 7)), isTrue);

      expect(weekly.toMap(), {
        'team_id': 'team-a',
        'weekday': 6,
        'start_time': '09:30:00',
      });
      expect(fromNovember.toMap()['starts_on'], '2026-11-01');
      final loaded = Availability.fromMap({
        'id': 'a1',
        'team_id': 'team-a',
        'weekday': 6,
        'start_time': '09:30:00',
        'starts_on': null,
        'starts_at': null,
      });
      expect(loaded.isWeekly, isTrue);
      expect(loaded.startTime, const TimeOfDay(hour: 9, minute: 30));

      final withSkip = Availability.fromMap({
        'id': 'a1',
        'team_id': 'team-a',
        'weekday': 6,
        'start_time': '09:30:00',
        'starts_on': null,
        'starts_at': null,
        'team_availability_skips': [
          {'on_date': '2026-10-31'},
        ],
      });
      expect(withSkip.occursOn(DateTime(2026, 10, 24)), isTrue);
      expect(withSkip.occursOn(DateTime(2026, 10, 31)), isFalse);
      expect(everyWeekday(DateTime.saturday), 'Todo sábado');
      expect(everyWeekday(DateTime.monday), 'Toda segunda');
    });

    testWidgets('remove um dia do recorrente ou todas as semanas', (
      tester,
    ) async {
      final availability = FakeAvailabilityRepository(
        byTeam: {
          'team-a': [
            const Availability.weekly(
              id: 'w1',
              teamId: 'team-a',
              weekday: DateTime.saturday,
              startTime: TimeOfDay(hour: 15, minute: 0),
            ),
            Availability.single(
              id: 's1',
              teamId: 'team-a',
              startsAt: DateTime(2026, 10, 24, 18),
            ),
          ],
        },
      );
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        availability: availability,
      );
      // Sábado, 24/10/2026.
      await _pumpPage(
        tester,
        container,
        AvailabilityPage(today: DateTime(2026, 10, 24)),
      );
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
      // Tira a lista de baixo do botão "Adicionar horário".
      await tester.drag(find.text('15:00'), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Imprevisto: tira só este sábado do recorrente.
      await tester.tap(find.byTooltip('Remover horário').first);
      await tester.pumpAndSettle();
      expect(find.text('Todas as semanas'), findsOneWidget);
      await tester.tap(find.text('Só em 24/10/2026'));
      await tester.pumpAndSettle();

      expect(availability.skipped.single, (
        availabilityId: 'w1',
        date: DateTime(2026, 10, 24),
      ));
      expect(availability.deleted, isEmpty);
      expect(find.text('15:00'), findsNothing);
      expect(find.text('18:00'), findsOneWidget);
      // O recorrente continua nas outras semanas.
      await tester.scrollUntilVisible(
        find.text('Todo sábado às 15:00'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Sem jogo em 24/10/2026'), findsOneWidget);

      // O avulso sai de vez, com a confirmação de sempre.
      await tester.tap(find.byTooltip('Remover horário'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(availability.deleted, ['s1']);

      // Pela lista de recorrentes, sai de todas as semanas.
      await tester.tap(find.byTooltip('Remover horário recorrente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      expect(availability.deleted, ['s1', 'w1']);
      expect(find.text('Recorrentes'), findsNothing);
    });

    testWidgets('edita o horário de um dia ou de todas as semanas', (
      tester,
    ) async {
      // Tela de celular em pé: o seletor de horário digitado não cabe na tela
      // deitada padrão dos testes.
      tester.view
        ..physicalSize = const Size(1080, 2340)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final availability = FakeAvailabilityRepository(
        byTeam: {
          'team-a': [
            const Availability.weekly(
              id: 'w1',
              teamId: 'team-a',
              weekday: DateTime.saturday,
              startTime: TimeOfDay(hour: 15, minute: 0),
            ),
            Availability.single(
              id: 's1',
              teamId: 'team-a',
              startsAt: DateTime(2026, 10, 24, 18),
            ),
          ],
        },
      );
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        availability: availability,
      );
      // Sábado, 24/10/2026.
      await _pumpPage(
        tester,
        container,
        AvailabilityPage(today: DateTime(2026, 10, 24)),
      );
      await tester.drag(find.text('15:00'), const Offset(0, -300));
      await tester.pumpAndSettle();

      Future<void> pickTime(String hour, String minute) async {
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pumpAndSettle();
        final fields = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(fields.at(0), hour);
        await tester.pump();
        await tester.enterText(fields.at(1), minute);
        await tester.pump();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      // Avulso: muda o horário direto.
      await tester.tap(find.byTooltip('Editar horário').last);
      await tester.pumpAndSettle();
      expect(find.text('Novo horário'), findsOneWidget);
      await pickTime('19', '30');
      expect(availability.updated.single.id, 's1');
      expect(
        availability.updated.single.startsAt,
        DateTime(2026, 10, 24, 19, 30),
      );
      expect(find.text('19:30'), findsOneWidget);
      expect(find.text('18:00'), findsNothing);

      // Recorrente, todas as semanas: muda o horário do recorrente.
      await tester.tap(find.byTooltip('Editar horário').first);
      await tester.pumpAndSettle();
      await pickTime('17', '00');
      expect(find.text('Mudar para 17:00?'), findsOneWidget);
      await tester.tap(find.text('Todas as semanas'));
      await tester.pumpAndSettle();
      final weekly = availability.updated.last;
      expect(weekly.id, 'w1');
      expect(weekly.startTime, const TimeOfDay(hour: 17, minute: 0));
      expect(find.text('17:00'), findsOneWidget);

      // Recorrente, só neste dia: vira avulso e o dia sai do recorrente.
      await tester.tap(find.byTooltip('Editar horário').first);
      await tester.pumpAndSettle();
      await pickTime('16', '00');
      await tester.tap(find.text('Só em 24/10/2026'));
      await tester.pumpAndSettle();
      expect(availability.added.single.startsAt, DateTime(2026, 10, 24, 16));
      expect(availability.skipped.single, (
        availabilityId: 'w1',
        date: DateTime(2026, 10, 24),
      ));
      expect(find.text('16:00'), findsOneWidget);
      expect(find.text('17:00'), findsNothing);
      expect(availability.deleted, isEmpty);
    });

    testWidgets('cadastra horário recorrente e mostra no dia', (tester) async {
      final availability = FakeAvailabilityRepository();
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        availability: availability,
      );
      // Sábado, 24/10/2026.
      await _pumpPage(
        tester,
        container,
        AvailabilityPage(today: DateTime(2026, 10, 24)),
      );

      expect(find.textContaining('Nenhum horário neste dia'), findsOneWidget);
      await tester.tap(find.text('Adicionar horário'));
      await tester.pumpAndSettle();
      expect(find.text('Todo sábado neste horário'), findsOneWidget);
      await tester.tap(find.text('Repetir toda semana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      final added = availability.added.single;
      expect(added.isWeekly, isTrue);
      expect(added.weekday, DateTime.saturday);
      expect(added.startTime, const TimeOfDay(hour: 15, minute: 0));
      expect(added.startsOn, DateTime(2026, 10, 24));
      expect(find.text('Todo sábado'), findsOneWidget);
      // Rolar arrastando por cima do calendário também move a tela.
      await tester.scrollUntilVisible(
        find.text('Todo sábado às 15:00'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Todo sábado às 15:00'), findsOneWidget);
    });

    testWidgets('a escolha do horário só oferece os horários livres', (
      tester,
    ) async {
      final availability = FakeAvailabilityRepository(
        freeByTeam: {
          'team-rival': [
            DateTime(2026, 10, 24, 15),
            DateTime(2026, 10, 24, 18),
            DateTime(2026, 10, 31, 15),
          ],
        },
      );
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        availability: availability,
      );
      await _pumpPage(
        tester,
        container,
        SlotPickerPage(
          teamId: 'team-rival',
          calendarOwner: 'do Real Bairro',
          today: DateTime(2026, 10, 22),
        ),
      );

      // Abre no primeiro dia com horário livre.
      expect(find.text('Horários em 24/10/2026'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);

      // Dia sem horário não é selecionável.
      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      expect(find.text('Horários em 24/10/2026'), findsOneWidget);

      await tester.tap(find.text('31'));
      await tester.pumpAndSettle();
      expect(find.text('Horários em 31/10/2026'), findsOneWidget);
      // Escolher o horário fecha a tela.
      await tester.tap(find.text('15:00'));
      await tester.pumpAndSettle();
      expect(find.text('Início'), findsOneWidget);
    });

    testWidgets('contra time fictício vale o calendário do próprio time', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 2));
      final mySlot = DateTime(soon.year, soon.month, soon.day, 20);
      final availability = FakeAvailabilityRepository(
        freeByTeam: {
          'team-a': [mySlot],
        },
      );
      final games = FakeGameRepository({});
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        games: games,
        availability: availability,
        venues: FakeVenueRepository([arena]),
        opponents: FakeOpponentRepository(
          guests: const [
            GuestTeam(
              id: 'guest-1',
              ownerId: 'u1',
              name: 'Pelada de Sábado',
              modality: Modality.society,
            ),
          ],
        ),
      );
      await _pumpPage(tester, container, const GameFormPage());

      // Sem adversário, o horário ainda não pode ser escolhido.
      expect(find.text('Escolha o adversário primeiro'), findsOneWidget);
      await tester.ensureVisible(find.text('Data e hora'));
      await tester.tap(find.text('Data e hora'));
      await tester.pumpAndSettle();
      expect(find.text('Escolher dia e horário'), findsNothing);

      await tester.tap(find.widgetWithText(InputDecorator, 'Adversário'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pelada de Sábado'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Data e hora'));
      await tester.tap(find.text('Data e hora'));
      await tester.pumpAndSettle();
      expect(availability.freeSlotRequests.last, 'team-a');
      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();

      final venueField = find.widgetWithText(InputDecorator, 'Local');
      await tester.ensureVisible(venueField);
      await tester.tap(venueField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arena Society Central'));
      await tester.pumpAndSettle();

      final submit = find.text('Marcar amistoso');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(games.created.single.scheduledAt, mySlot);
      expect(games.created.single.opponentGuestId, 'guest-1');
      expect(games.created.single.venueId, 'venue-1');
    });
  });

  group('locais', () {
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> fillAddress(WidgetTester tester, String name) async {
      Finder field(String label) => find.widgetWithText(TextFormField, label);
      await tester.enterText(field('Nome do local'), name);
      await tester.enterText(field('Rua'), 'Rua das Flores');
      await tester.enterText(field('Número'), '120');
      await tester.enterText(field('Bairro'), 'Centro');
      await tester.enterText(field('Cidade'), 'Campinas');
      await tester.enterText(field('UF'), 'sp');
      // CEP por último: com 8 dígitos ele consultaria o ViaCEP; aqui o
      // campo é preenchido direto, sem o onChanged.
      tester.widget<TextFormField>(field('CEP')).controller!.text = '13010000';
      await tester.pump();
    }

    testWidgets('sugere o local que já existe em vez de cadastrar outro', (
      tester,
    ) async {
      final venues = FakeVenueRepository([arena]);
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        venues: venues,
      );
      await _pumpPage(tester, container, const VenuesPage(picking: true));

      // Pesquisa sem achar e cadastra um novo com o nome digitado.
      await tester.enterText(find.byType(TextField), 'Arena Society');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Arena Society Central'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'arena society c');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Cadastrar local'));
      expect(find.text('Novo local'), findsOneWidget);
      expect(find.text('arena society c'), findsOneWidget);

      await fillAddress(tester, 'Arena Society');
      await tapVisible(tester, find.text('Cadastrar local'));

      // Sugere o existente; escolher ele volta para o amistoso sem cadastrar.
      expect(venues.similarChecks.single.name, 'Arena Society');
      expect(find.text('Esse local já existe?'), findsOneWidget);
      await tapVisible(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Arena Society Central'),
        ),
      );
      expect(venues.created, isEmpty);
      expect(find.text('Início'), findsOneWidget);
    });

    testWidgets('cadastra mesmo assim quando não é o mesmo local', (
      tester,
    ) async {
      final venues = FakeVenueRepository([arena]);
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        venues: venues,
      );
      await _pumpPage(tester, container, const VenueFormPage());

      await fillAddress(tester, 'Arena Society');
      await tapVisible(tester, find.text('Cadastrar local'));
      expect(find.text('Esse local já existe?'), findsOneWidget);
      await tapVisible(tester, find.text('Cadastrar mesmo assim'));

      final created = venues.created.single;
      expect(created.name, 'Arena Society');
      expect(created.createdBy, 'u1');
      expect(created.toMap()['state'], 'SP');
      expect(created.address, 'Rua das Flores, 120 - Centro, Campinas/SP');
      expect(find.text('Início'), findsOneWidget);
    });

    testWidgets('sem parecidos, cadastra direto', (tester) async {
      final venues = FakeVenueRepository([arena]);
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        venues: venues,
      );
      await _pumpPage(tester, container, const VenueFormPage());

      await tapVisible(tester, find.text('Cadastrar local'));
      expect(find.text('Informe o nome do local'), findsOneWidget);
      expect(venues.created, isEmpty);

      await fillAddress(tester, 'Ginásio Municipal');
      await tapVisible(tester, find.text('Cadastrar local'));
      expect(find.text('Esse local já existe?'), findsNothing);
      expect(venues.created.single.name, 'Ginásio Municipal');
    });
  });
}
