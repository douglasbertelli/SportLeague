import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/media/picked_image.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/athletes/presentation/athlete_form_page.dart';
import 'package:sport_league/features/athletes/presentation/athletes_tab.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/features/games/data/opponent_repository.dart';
import 'package:sport_league/features/games/domain/opponent.dart';
import 'package:sport_league/features/games/presentation/game_form_page.dart';
import 'package:sport_league/features/games/presentation/opponent_picker_page.dart';
import 'package:sport_league/features/games/presentation/games_tab.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';
import 'package:sport_league/features/teams/presentation/team_form_page.dart';

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
          final (:teamId, :modality) =
              state.extra as ({String teamId, Modality modality});
          return OpponentPickerPage(teamId: teamId, modality: modality);
        },
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

      expect(find.text('x Real Bairro'), findsOneWidget);
      expect(find.text('Society'), findsOneWidget);
      expect(find.text('x Outro Time'), findsNothing);

      await tester.tap(find.text('Pendentes (1)'));
      await tester.pumpAndSettle();
      expect(find.text('x Vila Nova'), findsOneWidget);
      expect(
        find.textContaining('Aguardando Vila Nova aceitar'),
        findsOneWidget,
      );
      // Quem marcou não aceita o próprio amistoso.
      expect(find.text('Aceitar'), findsNothing);

      await tester.tap(find.text('Cancelados (1)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cancelado por Desistentes FC'),
        findsOneWidget,
      );

      await tester.tap(find.text('Realizados (1)'));
      await tester.pumpAndSettle();
      expect(find.text('x Unidos da Vila'), findsOneWidget);
      expect(find.text('Vitória 3 x 1'), findsOneWidget);
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
      expect(find.textContaining('Aguardando sua resposta'), findsNWidgets(2));

      await tester.tap(find.text('Aceitar').first);
      await tester.pumpAndSettle();
      expect(games.accepted, ['g1']);

      await tester.tap(find.text('Recusar').last);
      await tester.pumpAndSettle();
      expect(find.text('Recusar amistoso?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Recusar').last);
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

      expect(find.text('x Amigos FC'), findsOneWidget);
      await tester.tap(find.text('Cancelar amistoso'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, 'Cancelar amistoso').last,
      );
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

    testWidgets('sem tipo e sem placar; exige modalidade, adversário e data', (
      tester,
    ) async {
      final games = FakeGameRepository({});
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        games: games,
      );
      await _pumpPage(tester, container, const GameFormPage());

      expect(find.text('Amistoso'), findsNothing);
      expect(find.text('Campeonato'), findsNothing);
      expect(find.textContaining('Placar'), findsNothing);

      await tapVisible(tester, find.text('Marcar amistoso'));

      expect(find.text('Escolha a modalidade do jogo'), findsOneWidget);
      expect(find.text('Escolha o adversário'), findsOneWidget);
      expect(find.text('Escolha a data e a hora'), findsOneWidget);
      expect(games.created, isEmpty);

      // Sem modalidade, a pesquisa do adversário não abre.
      await tapVisible(tester, opponentField);
      expect(find.text('Escolher adversário'), findsNothing);
    });

    testWidgets('pesquisa só a modalidade escolhida e salva o adversário', (
      tester,
    ) async {
      final games = FakeGameRepository({});
      final opponents = FakeOpponentRepository(
        registered: [rival],
        guests: [guest],
      );
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        games: games,
        opponents: opponents,
      );
      final game = Game(
        id: 'g1',
        teamId: 'team-a',
        opponent: 'Antigo FC',
        scheduledAt: DateTime(2026, 10, 25, 15),
      );
      await _pumpPage(tester, container, GameFormPage(game: game));

      await tapVisible(tester, find.text('Society'));
      await tapVisible(tester, opponentField);
      expect(find.text('Escolher adversário'), findsOneWidget);
      expect(opponents.searches.last.modality, Modality.society);
      expect(opponents.searches.last.teamId, 'team-a');

      await tester.enterText(find.byType(TextField), 'real');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(opponents.searches.last.query, 'real');

      await tapVisible(tester, find.text('Real Bairro'));
      expect(find.text('Real Bairro'), findsOneWidget);

      await tapVisible(tester, find.text('Salvar'));
      final saved = games.updated.single;
      expect(saved.opponent, 'Real Bairro');
      expect(saved.opponentTeamId, 'team-rival');
      expect(saved.opponentGuestId, isNull);
      expect(saved.modality, Modality.society);
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

      await tapVisible(tester, find.text('Campo'));
      await tapVisible(tester, opponentField);
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

    testWidgets('trocar a modalidade limpa o adversário escolhido', (
      tester,
    ) async {
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        opponents: FakeOpponentRepository(registered: [rival]),
      );
      await _pumpPage(tester, container, const GameFormPage());

      await tapVisible(tester, find.text('Society'));
      await tapVisible(tester, opponentField);
      await tapVisible(tester, find.text('Real Bairro'));
      expect(find.text('Real Bairro'), findsOneWidget);

      await tapVisible(tester, find.text('Campo'));
      expect(find.text('Real Bairro'), findsNothing);
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
    expect(find.text('x Amigos FC'), findsOneWidget);
    expect(find.textContaining('Marcado por Amigos FC'), findsOneWidget);
    expect(find.text('Vitória 2 x 0'), findsOneWidget);
    // Só quem marcou edita.
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('x Amigos FC'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.onTap, isNull);
  });
}
