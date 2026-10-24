import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
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
import 'package:sport_league/features/home/presentation/team_dashboard.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';
import 'package:sport_league/features/teams/presentation/team_form_page.dart';
import 'package:sport_league/features/teams/domain/team_stats.dart';
import 'package:sport_league/features/teams/presentation/team_profile_page.dart';
import 'package:sport_league/features/teams/presentation/team_search_page.dart';
import 'package:sport_league/features/venues/data/venue_repository.dart';
import 'package:sport_league/features/venues/domain/venue.dart';
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
          final (:teamId, :modalities, :modality, :playsAs) =
              state.extra as OpponentPickerArgs;
          return OpponentPickerPage(
            teamId: teamId,
            modalities: modalities,
            modality: modality,
            playsAs: playsAs,
          );
        },
      ),
      GoRoute(
        path: Routes.teamProfile,
        builder: (_, state) => TeamProfilePage(teamId: state.extra as String),
      ),
      GoRoute(
        path: Routes.pickVenue,
        builder: (_, _) => const VenuesPage(picking: true),
      ),
      GoRoute(
        path: Routes.newVenue,
        builder: (_, state) => switch (state.extra) {
          final NewVenueArgs args => VenueFormPage(
            initialName: args.name,
            offerTeamLink: args.offerTeamLink,
          ),
          _ => const VenueFormPage(),
        },
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

/// Tela de celular em pé (360x780), para listas longas como a disponibilidade.
void _usePhoneScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
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
        'min_age': null,
        'max_age': null,
        'founded_on': null,
        'logo_url': null,
        'description': null,
        'city': null,
        'state': 'SP',
        'plays_as': 'both',
        'phone': null,
        'instagram': null,
        'facebook': null,
        'youtube': null,
        'website': null,
        'cover_url': null,
        'kit_urls': <String>[],
        'home_venue_id': null,
      });
      expect(teamB.location, 'Campinas/SP');
      expect(teamA.location, isNull);

      // Contatos: telefone só com dígitos e Instagram sem o "@".
      const contacts = Team(
        ownerId: 'u1',
        name: 'Amigos FC',
        phone: '(19) 99999-8888',
        instagram: ' @amigosfc ',
        website: ' ',
      );
      expect(contacts.toMap()['phone'], '19999998888');
      expect(contacts.toMap()['instagram'], 'amigosfc');
      expect(contacts.toMap()['website'], isNull);
      expect(formatPhone('19999998888'), '(19) 99999-8888');
      expect(formatPhone('1933334444'), '(19) 3333-4444');
    });

    test('a fonte do app é a DM Sans', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(theme.textTheme.bodyMedium?.fontFamily, 'DM Sans');
        expect(theme.textTheme.titleLarge?.fontFamily, 'DM Sans');
        expect(theme.listTileTheme.subtitleTextStyle?.fontFamily, 'DM Sans');
      }
    });

    test('subtítulos em cinza neutro, mais fracos que os títulos', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final grey = theme.colorScheme.onSurfaceVariant;
        // Cinza: vermelho, verde e azul iguais (sem o tom verde do tema).
        expect(grey.r, grey.g);
        expect(grey.g, grey.b);
        expect(theme.listTileTheme.subtitleTextStyle?.color, grey);
        expect(grey, isNot(theme.colorScheme.onSurface));
      }
    });

    test('faixa de idade: limites de Base e Master', () {
      const youth = Team(
        ownerId: 'u1',
        name: 'Sub 15',
        ageGroup: AgeGroup.youth,
        minAge: 13,
        maxAge: 15,
      );
      expect(youth.ageRange, '13 a 15 anos');
      expect(youth.toMap()['min_age'], 13);
      expect(youth.toMap()['max_age'], 15);

      const master = Team(
        ownerId: 'u1',
        name: 'Veteranos',
        ageGroup: AgeGroup.master,
        minAge: 40,
        maxAge: 50,
      );
      expect(master.ageRange, 'A partir de 40 anos');
      expect(master.summary, 'Master 40+');
      // Master não tem idade máxima; Livre não tem limites.
      expect(master.toMap()['max_age'], isNull);
      const open = Team(ownerId: 'u1', name: 'Livre FC', minAge: 10);
      expect(open.toMap()['min_age'], isNull);
    });

    test('joga como: mandante, visitante ou ambos', () {
      expect(PlaysAs.both.accepts(home: true), isTrue);
      expect(PlaysAs.both.accepts(home: false), isTrue);
      expect(PlaysAs.home.accepts(home: false), isFalse);
      expect(PlaysAs.away.accepts(home: true), isFalse);
      expect(PlaysAs.away.accepts(home: false), isTrue);
    });

    test('modalidade, gênero, faixa de idade e fundação vão e voltam', () {
      final team = Team.fromMap({
        'id': 't1',
        'owner_id': 'u1',
        'name': 'Areia FC',
        'sport': 'football',
        'modalities': ['challenge', 'beach', 'futsal'],
        'gender': 'female',
        'age_group': 'master',
        'founded_on': '2015-03-08',
        'logo_url': 'https://storage.test/logo',
        'plays_as': 'away',
        'instagram': 'areiafc',
        'cover_url': 'https://storage.test/cover',
        'kit_urls': [
          'https://storage.test/kit-1',
          'https://storage.test/kit-2',
        ],
      });

      expect(team.modalities, {
        Modality.futsal,
        Modality.beach,
        Modality.challenge,
      });
      expect(team.gender, TeamGender.female);
      expect(team.ageGroup, AgeGroup.master);
      expect(team.foundedOn, DateTime(2015, 3, 8));
      // Master antigo, sem idade gravada: vale a sugerida (35).
      expect(team.summary, 'Futsal, Areia, Desafio · Feminino · Master 35+');
      expect(team.ageRange, 'A partir de 35 anos');
      expect(team.toMap()['modalities'], ['futsal', 'beach', 'challenge']);
      expect(team.toMap()['founded_on'], '2015-03-08');
      expect(team.playsAs, PlaysAs.away);
      expect(team.hasContacts, isTrue);
      expect(team.coverUrl, 'https://storage.test/cover');
      expect(team.kitUrls, hasLength(2));

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
      expect(old.playsAs, PlaysAs.both);
      expect(old.hasContacts, isFalse);
      expect(old.kitUrls, isEmpty);
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

    testWidgets('as abas Time e Detalhes conferem os obrigatórios', (
      tester,
    ) async {
      final teams = FakeTeamRepository([teamA]);
      final container = await _container(teams: teams);
      await _pumpPage(tester, container, const TeamFormPage());

      await tester.enterText(find.byType(TextFormField).first, 'Várzea United');
      // Pular para a aba Mídia confere antes a aba Time.
      await tapVisible(tester, 'Mídia');
      expect(find.text('Escolha a modalidade'), findsOneWidget);
      expect(find.text('Escolha o gênero'), findsOneWidget);
      expect(find.text('Adicionar capa'), findsNothing);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);

      await tapVisible(tester, 'Society');
      await tapVisible(tester, 'Masculino');
      await tapVisible(tester, 'Próximo');

      // Aba Detalhes: mando, fundação e cidade.
      expect(find.text('Joga como'), findsOneWidget);
      await tapVisible(tester, 'Próximo');
      expect(find.text('Informe a data de fundação'), findsOneWidget);
      expect(find.text('Informe a cidade'), findsOneWidget);
      expect(find.text('Informe a UF'), findsOneWidget);
      expect(find.text('Telefone / WhatsApp'), findsNothing);

      // Voltar não confere nada.
      await tapVisible(tester, 'Time');
      expect(find.text('Nome do time'), findsOneWidget);
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
        pickImage: (source, {maxSize = smallImageSize}) async => logo,
      );
      await _pumpPage(tester, container, const TeamFormPage());

      await tester.tap(find.bySemanticsLabel('Adicionar logo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escolher da galeria'));
      await tester.pumpAndSettle();

      Finder field(String label) => find.widgetWithText(TextFormField, label);

      // Aba 1: time.
      await tester.enterText(find.byType(TextFormField).first, 'Várzea United');
      await tapVisible(tester, 'Society');
      await tapVisible(tester, 'Desafio');
      await tapVisible(tester, 'Feminino');
      await tapVisible(tester, 'Base');
      // Base vem com 4 a 20 anos; o administrador ajusta (sub-15).
      expect(find.text('4 a 20 anos'), findsOneWidget);
      await tester.enterText(field('Idade mínima'), '16');
      await tester.enterText(field('Idade máxima'), '15');
      await tapVisible(tester, 'Próximo');
      expect(find.text('Entre 16 e 25'), findsOneWidget);
      await tester.enterText(field('Idade mínima'), '13');
      await tester.pump();
      expect(find.text('13 a 15 anos'), findsOneWidget);
      await tapVisible(tester, 'Próximo');

      // Aba 2: detalhes.
      await tapVisible(tester, 'Visitante');
      expect(find.text(PlaysAs.away.description), findsOneWidget);
      await tapVisible(tester, 'Data de fundação');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Cidade'), 'Campinas');
      await tester.enterText(field('UF'), 'sp');
      await tapVisible(tester, 'Próximo');

      // Aba 3: contato.
      expect(find.text('Telefone / WhatsApp'), findsOneWidget);
      await tester.enterText(field('Telefone / WhatsApp'), '199');
      await tapVisible(tester, 'Próximo');
      expect(find.text('Informe o DDD e o número'), findsOneWidget);
      await tester.enterText(field('Telefone / WhatsApp'), '19999998888');
      await tester.enterText(field('Instagram'), 'varzea.united');
      await tapVisible(tester, 'Próximo');

      // Aba 4: mídia — capa e dois uniformes.
      await tapVisible(tester, 'Adicionar capa');
      await tapVisible(tester, 'Escolher da galeria');
      await tapVisible(tester, 'Adicionar uniforme');
      await tapVisible(tester, 'Escolher da galeria');
      await tapVisible(tester, 'Adicionar uniforme');
      await tapVisible(tester, 'Escolher da galeria');
      expect(find.bySemanticsLabel('Uniforme 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Adicionar uniforme'), findsOneWidget);
      await tapCreate(tester);

      final created = teams.created.single;
      expect(created.name, 'Várzea United');
      expect(created.ownerId, 'u1');
      // Uma modalidade só: escolher Desafio troca a Society.
      expect(created.modalities, {Modality.challenge});
      expect(created.playsAs, PlaysAs.away);
      expect(created.gender, TeamGender.female);
      expect(created.ageGroup, AgeGroup.youth);
      expect(created.toMap()['min_age'], 13);
      expect(created.toMap()['max_age'], 15);
      expect(created.summary, 'Desafio · Feminino · Base 13-15');
      expect(created.foundedOn, isNotNull);
      expect(created.toMap()['city'], 'Campinas');
      expect(created.toMap()['state'], 'SP');
      expect(created.toMap()['phone'], '19999998888');
      expect(created.toMap()['instagram'], 'varzea.united');
      expect(created.logoUrl, isNull);
      expect(created.kitUrls, isEmpty);

      // Depois de criado, as imagens são enviadas e as URLs gravadas no time.
      final active = await container.read(selectedTeamProvider.future);
      expect(active?.name, 'Várzea United');
      expect(teams.uploadedLogos[active!.id], same(logo));
      expect(teams.uploadedCovers[active.id], same(logo));
      expect(teams.uploadedKits, hasLength(2));
      final saved = teams.updated.last;
      expect(saved.logoUrl, 'https://storage.test/team-logos/u1/${active.id}');
      expect(
        saved.coverUrl,
        'https://storage.test/team-logos/u1/${active.id}-cover',
      );
      expect(saved.kitUrls, [
        'https://storage.test/team-logos/u1/${active.id}-kit-1',
        'https://storage.test/team-logos/u1/${active.id}-kit-2',
      ]);
      expect(find.text('Início'), findsOneWidget);
    });

    testWidgets('editar remove um uniforme e salva de qualquer etapa', (
      tester,
    ) async {
      final team = Team(
        id: 'team-k',
        ownerId: 'u1',
        name: 'Kits FC',
        modalities: const {Modality.society},
        gender: TeamGender.male,
        foundedOn: DateTime(2010),
        city: 'Campinas',
        state: 'SP',
        kitUrls: const [
          'https://storage.test/team-logos/u1/team-k-kit-a',
          'https://storage.test/team-logos/u1/team-k-kit-b',
        ],
      );
      final teams = FakeTeamRepository([team]);
      final container = await _container(teams: teams);
      await _pumpPage(tester, container, TeamFormPage(team: team));

      await tapVisible(tester, 'Mídia');
      await tester.ensureVisible(find.bySemanticsLabel('Uniforme 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Uniforme 1'));
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Remover uniforme');
      expect(find.bySemanticsLabel('Uniforme 2'), findsNothing);
      await tapVisible(tester, 'Contato');
      await tapVisible(tester, 'Salvar');

      expect(teams.updated.single.kitUrls, [
        'https://storage.test/team-logos/u1/team-k-kit-b',
      ]);
      expect(teams.removedImages, [
        'https://storage.test/team-logos/u1/team-k-kit-a',
      ]);
    });

    testWidgets('o perfil mostra mando, uniformes e contatos', (tester) async {
      // Tela de celular em pé, para caber o perfil inteiro.
      tester.view
        ..physicalSize = const Size(1080, 2340)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const rival = Team(
        id: 'team-rival',
        ownerId: 'u2',
        name: 'Real Bairro',
        modalities: {Modality.society},
        playsAs: PlaysAs.away,
        phone: '19999998888',
        instagram: 'realbairro',
        kitUrls: ['https://storage.test/kit-1'],
      );
      final teams = FakeTeamRepository([teamA, rival]);
      teams.statsByTeam['team-rival'] = TeamStats(
        played: 3,
        wins: 1,
        draws: 1,
        losses: 0,
        goalsFor: 4,
        goalsAgainst: 2,
        recent: [
          ProfileGame(
            scheduledAt: DateTime(2026, 10, 18, 15),
            opponent: 'Vila Nova',
            isHome: false,
            goalsFor: 3,
            goalsAgainst: 1,
          ),
          ProfileGame(
            scheduledAt: DateTime(2026, 10, 11, 15),
            opponent: 'Bola Murcha',
            isHome: true,
          ),
        ],
      );
      teams.follows.add((follower: 'team-b', followed: 'team-rival'));
      final container = await _container(teams: teams);
      await _pumpPage(
        tester,
        container,
        const TeamProfilePage(teamId: 'team-rival'),
      );
      final list = find.byType(Scrollable).first;
      Future<void> scrollTo(Finder finder) =>
          tester.scrollUntilVisible(finder, 200, scrollable: list);

      // Seguidores (1: o Bola Murcha) e o botão Seguir pelo time ativo.
      expect(find.text('Seguidores'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      await tester.tap(find.text('Seguir'));
      await tester.pumpAndSettle();
      expect(
        teams.follows,
        contains((follower: 'team-a', followed: 'team-rival')),
      );
      expect(find.text('Seguindo'), findsWidgets);
      expect(find.text('2'), findsWidgets);

      // Estatísticas e últimos resultados (V, e sem placar).
      await scrollTo(find.text('Últimos resultados'));
      expect(find.text('Vitórias'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('3 × 1'), findsOneWidget);
      // "x Adversário" com o selo Casa ou Fora, sem o @.
      expect(find.text('x Vila Nova'), findsOneWidget);
      expect(find.text('Fora'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.textContaining('@ '), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.semanticsLabel == 'Vitória',
        ),
        findsOneWidget,
      );
      expect(find.text('Sem placar'), findsOneWidget);

      await scrollTo(find.text('Joga como: Visitante'));
      await scrollTo(find.text('Uniformes'));
      expect(find.bySemanticsLabel('Uniforme 1'), findsOneWidget);
      await scrollTo(find.text('@realbairro'));
      expect(find.text('(19) 99999-8888'), findsOneWidget);
    });

    testWidgets('no perfil do próprio time ativo não há Seguir', (
      tester,
    ) async {
      final container = await _container(teams: FakeTeamRepository([teamA]));
      await _pumpPage(
        tester,
        container,
        const TeamProfilePage(teamId: 'team-a'),
      );
      expect(find.text('Seguidores'), findsOneWidget);
      expect(find.text('Seguir'), findsNothing);
    });

    testWidgets('a pesquisa lista os times e abre o perfil', (tester) async {
      final container = await _container(
        teams: FakeTeamRepository([teamA, teamB]),
      );
      await _pumpPage(tester, container, const TeamSearchPage());
      expect(find.text('Amigos FC'), findsOneWidget);
      expect(find.text('Bola Murcha'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bola');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Amigos FC'), findsNothing);
      // Card como o da escolha de adversário: resumo e cidade.
      expect(find.text('Society · Livre\nCampinas/SP'), findsOneWidget);

      await tester.tap(find.text('Bola Murcha'));
      await tester.pumpAndSettle();
      expect(find.text('Seguidores'), findsOneWidget);
    });

    test('números do perfil vêm do banco', () {
      final stats = TeamStats.fromMap({
        'played': 4,
        'wins': 2,
        'draws': 1,
        'losses': 1,
        'goals_for': 7,
        'goals_against': 5,
        'followers': 3,
        'following': 1,
        'recent': [
          {
            'scheduled_at': '2026-10-18T18:00:00+00:00',
            'opponent': 'Vila Nova',
            'is_home': true,
            'goals_for': 1,
            'goals_against': 1,
          },
        ],
        'upcoming': <Object>[],
      });
      expect(stats.goalDifference, 2);
      expect(stats.recent.single.outcome, 'E');
      expect(stats.followers, 3);
      // Sem placar, sem resultado.
      expect(
        ProfileGame(
          scheduledAt: DateTime(2026, 10, 1),
          opponent: 'X',
          isHome: true,
        ).outcome,
        isNull,
      );
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
      // Quem marcou não aceita o próprio amistoso: edita ou cancela. O menu
      // abre num bottom sheet, com ícones.
      await tester.tap(find.byTooltip('Ações do amistoso'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
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
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Recusar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(games.canceled, ['g2']);
    });

    testWidgets('o painel do Início mostra próximo jogo, pendências e forma', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      Game game(
        String id, {
        required String teamId,
        String? opponentTeamId,
        required GameStatus status,
        required DateTime at,
        String opponent = 'Real Bairro',
      }) => Game(
        id: id,
        teamId: teamId,
        opponent: opponent,
        opponentTeamId: opponentTeamId,
        status: status,
        modality: Modality.society,
        scheduledAt: at,
      );
      final games = FakeGameRepository({
        'team-a': [
          game(
            'g1',
            teamId: 'team-a',
            opponentTeamId: 'team-rival',
            status: GameStatus.scheduled,
            at: DateTime(2026, 10, 31, 15),
          ),
          game(
            'g2',
            teamId: 'team-a',
            opponentTeamId: 'team-vila',
            status: GameStatus.pending,
            at: DateTime(2026, 11, 7, 15),
            opponent: 'Vila Nova',
          ),
        ],
        'team-rival': [
          game(
            'g3',
            teamId: 'team-rival',
            opponentTeamId: 'team-a',
            status: GameStatus.pending,
            at: DateTime(2026, 11, 14, 15),
            opponent: 'Amigos FC',
          ),
        ],
      });
      final teams = FakeTeamRepository([teamA]);
      teams.statsByTeam['team-a'] = TeamStats(
        played: 2,
        wins: 1,
        losses: 1,
        recent: [
          ProfileGame(
            scheduledAt: DateTime(2026, 10, 18),
            opponent: 'Vila Nova',
            isHome: true,
            goalsFor: 2,
            goalsAgainst: 0,
          ),
          ProfileGame(
            scheduledAt: DateTime(2026, 10, 11),
            opponent: 'Bola Murcha',
            isHome: false,
            goalsFor: 0,
            goalsAgainst: 1,
          ),
        ],
      );
      var openedGames = false;
      final container = await _container(teams: teams, games: games);
      await _pumpTab(
        tester,
        container,
        SingleChildScrollView(
          child: TeamDashboard(
            now: DateTime(2026, 10, 22, 12),
            onOpenGames: () => openedGames = true,
          ),
        ),
      );

      expect(find.text('Amigos FC'), findsOneWidget);
      expect(find.text('0 seguidores · 0 seguindo'), findsOneWidget);
      // Próximo jogo: o marcado, não os pendentes.
      expect(find.text('x Real Bairro'), findsOneWidget);
      expect(find.text('31/10/2026 às 15:00'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      // Um convite para responder (g3) e um aguardando o adversário (g2).
      expect(find.text('1 convite para responder'), findsOneWidget);
      expect(find.text('1 amistoso aguardando o adversário'), findsOneWidget);
      await tester.tap(find.text('1 convite para responder'));
      expect(openedGames, isTrue);
      // Estatísticas e forma (V e D).
      expect(find.text('Vitórias'), findsOneWidget);
      Finder badge(String label) => find.byWidgetPredicate(
        (widget) => widget is Text && widget.semanticsLabel == label,
      );
      expect(badge('Vitória'), findsOneWidget);
      expect(badge('Derrota'), findsOneWidget);
    });

    testWidgets('quem marcou lança o placar depois do jogo', (tester) async {
      final games = FakeGameRepository({
        'team-a': [
          Game(
            id: 'g1',
            teamId: 'team-a',
            opponent: 'Real Bairro',
            opponentTeamId: 'team-rival',
            status: GameStatus.scheduled,
            modality: Modality.society,
            scheduledAt: DateTime(2026, 10, 18, 15),
          ),
        ],
      });
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        games: games,
      );
      await _pumpTab(
        tester,
        container,
        GamesTab(now: DateTime(2026, 10, 22, 12)),
      );

      await tester.tap(find.text('Realizados (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ações do amistoso'));
      await tester.pumpAndSettle();
      // Depois do jogo, a única ação é o placar.
      expect(find.text('Editar'), findsNothing);
      await tester.tap(find.text('Lançar placar'));
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextFormField),
      );
      await tester.tap(find.text('Salvar placar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe os gols'), findsNWidgets(2));
      await tester.enterText(fields.at(0), '3');
      await tester.enterText(fields.at(1), '1');
      await tester.tap(find.text('Salvar placar'));
      await tester.pumpAndSettle();
      expect(games.scores['g1'], (3, 1));
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
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Cancelar amistoso'),
        ),
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

    testWidgets('o local vem preenchido com o de quem joga em casa', (
      tester,
    ) async {
      const rivalVenue = Venue(
        id: 'venue-r',
        name: 'Campo do Real',
        zipCode: '13020000',
        street: 'Rua B',
        number: '1',
        neighborhood: 'Vila',
        city: 'Campinas',
        state: 'SP',
      );
      final home = Team(
        id: 'team-a',
        ownerId: 'u1',
        name: 'Amigos FC',
        modalities: const {Modality.society},
        homeVenue: arena,
      );
      final rivalWithVenue = Team(
        id: 'team-rival',
        ownerId: 'u2',
        name: 'Real Bairro',
        modalities: const {Modality.society},
        homeVenue: rivalVenue,
      );
      final container = await _container(
        teams: FakeTeamRepository([home]),
        opponents: FakeOpponentRepository(registered: [rivalWithVenue]),
        venues: FakeVenueRepository([arena, rivalVenue]),
      );
      await _pumpPage(tester, container, const GameFormPage());

      // Mandante: o local do próprio time.
      expect(find.text('Arena Society Central'), findsOneWidget);
      expect(find.textContaining('local do Amigos FC'), findsOneWidget);

      // Visitante contra time da plataforma: o local do adversário.
      await tapVisible(tester, opponentField);
      await tapVisible(tester, find.text('Real Bairro'));
      await tapVisible(tester, find.text('Visitante'));
      expect(find.text('Campo do Real'), findsOneWidget);
      expect(find.textContaining('local do Real Bairro'), findsOneWidget);

      // Escolhido à mão, não muda mais com o mando.
      await tapVisible(tester, find.widgetWithText(InputDecorator, 'Local'));
      await tapVisible(tester, find.text('Arena Society Central'));
      await tapVisible(tester, find.text('Mandante'));
      await tapVisible(tester, find.text('Visitante'));
      expect(find.text('Arena Society Central'), findsOneWidget);
      expect(find.textContaining('local do'), findsNothing);
    });

    testWidgets('o mando respeita como os dois times jogam', (tester) async {
      const host = Team(
        id: 'team-h',
        ownerId: 'u1',
        name: 'Sem Campo FC',
        modalities: {Modality.society},
        playsAs: PlaysAs.away,
      );
      const visitorOnly = Team(
        id: 'team-v',
        ownerId: 'u2',
        name: 'Também Visitante',
        modalities: {Modality.society},
        playsAs: PlaysAs.away,
      );
      const homeOnly = Team(
        id: 'team-m',
        ownerId: 'u3',
        name: 'Dono da Quadra',
        modalities: {Modality.society},
        playsAs: PlaysAs.home,
      );
      final container = await _container(
        teams: FakeTeamRepository([host]),
        opponents: FakeOpponentRepository(registered: [visitorOnly, homeOnly]),
      );
      await _pumpPage(tester, container, const GameFormPage());

      // O próprio time só joga fora: Mandante desabilitado, Visitante marcado.
      expect(
        find.text('O Sem Campo FC só joga como visitante.'),
        findsOneWidget,
      );
      final segments = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(segments.selected, {false});
      expect(segments.segments.first.enabled, isFalse);

      // Na pesquisa, outro time só visitante aparece desabilitado.
      await tapVisible(tester, opponentField);
      expect(
        find.textContaining('Só joga como visitante, como o seu time'),
        findsOneWidget,
      );
      final blocked = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Também Visitante'),
      );
      expect(blocked.enabled, isFalse);
      await tapVisible(tester, find.text('Dono da Quadra'));
      expect(find.text('Dono da Quadra'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {false},
      );
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
        pickImage: (source, {maxSize = smallImageSize}) async => photo,
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

    testWidgets('dias e horários com jogo ficam em vermelho', (tester) async {
      final games = FakeGameRepository({
        'team-a': [
          Game(
            id: 'g1',
            teamId: 'team-a',
            opponent: 'Real Bairro',
            opponentTeamId: 'team-rival',
            status: GameStatus.scheduled,
            scheduledAt: DateTime(2026, 10, 24, 15),
          ),
          Game(
            id: 'g2',
            teamId: 'team-a',
            opponent: 'Vila Nova',
            opponentTeamId: 'team-vila',
            status: GameStatus.pending,
            scheduledAt: DateTime(2026, 10, 31, 15),
          ),
          Game(
            id: 'g3',
            teamId: 'team-a',
            opponent: 'Cancelado FC',
            status: GameStatus.canceled,
            scheduledAt: DateTime(2026, 10, 28, 15),
          ),
        ],
      });
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        games: games,
        availability: FakeAvailabilityRepository(
          byTeam: {
            'team-a': [
              const Availability.weekly(
                id: 'w1',
                teamId: 'team-a',
                weekday: DateTime.saturday,
                startTime: TimeOfDay(hour: 15, minute: 0),
              ),
            ],
          },
        ),
      );
      _usePhoneScreen(tester);
      // Sábado, 24/10/2026.
      await _pumpPage(
        tester,
        container,
        AvailabilityPage(today: DateTime(2026, 10, 24)),
      );

      // Marcado e pendente pintam o dia; cancelado não.
      Finder bookedDay(String day) => find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.semanticsLabel == '$day, dia com jogo',
      );
      expect(bookedDay('24'), findsOneWidget);
      expect(bookedDay('31'), findsOneWidget);
      expect(bookedDay('28'), findsNothing);
      expect(find.text('Jogo contra Real Bairro'), findsOneWidget);
      final time = tester.widget<Text>(find.text('15:00'));
      expect(time.style?.color, AppTheme.dark().colorScheme.error);

      await tester.tap(bookedDay('31'));
      await tester.pumpAndSettle();
      expect(find.text('Aguardando resposta: Vila Nova'), findsOneWidget);
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
      _usePhoneScreen(tester);
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

      // O horário vem de um bottom sheet com rolagem (24 horas).
      Future<void> pickTime(String hour, String minute) async {
        expect(find.byType(BottomSheet), findsOneWidget);
        tester
            .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
            .onDateTimeChanged(
              DateTime(2000, 1, 1, int.parse(hour), int.parse(minute)),
            );
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
      }

      // Avulso: muda o horário direto.
      await tester.tap(find.byTooltip('Editar horário').last);
      await tester.pumpAndSettle();
      expect(find.text('Novo horário em 24/10/2026'), findsOneWidget);
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

    testWidgets('o calendário é o de quem joga em casa', (tester) async {
      final soon = DateTime.now().add(const Duration(days: 2));
      final mySlot = DateTime(soon.year, soon.month, soon.day, 20);
      final rivalSlot = DateTime(soon.year, soon.month, soon.day, 15);
      final availability = FakeAvailabilityRepository(
        freeByTeam: {
          'team-b': [mySlot],
          'team-rival': [rivalSlot],
        },
      );
      const rival = Team(
        id: 'team-rival',
        ownerId: 'u2',
        name: 'Real Bairro',
        modalities: {Modality.society},
      );
      final container = await _container(
        teams: FakeTeamRepository([teamB]),
        availability: availability,
        opponents: FakeOpponentRepository(registered: [rival]),
      );
      await _pumpPage(tester, container, const GameFormPage());
      Future<void> tapVisible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      // Mandante: o calendário do próprio time, já antes do adversário.
      expect(
        find.text('Horários livres no calendário do Bola Murcha'),
        findsOneWidget,
      );
      await tapVisible(find.widgetWithText(InputDecorator, 'Data e hora'));
      expect(availability.freeSlotRequests.last, 'team-b');
      await tapVisible(find.text('20:00'));
      await tapVisible(find.widgetWithText(InputDecorator, 'Adversário'));
      await tapVisible(find.text('Real Bairro'));
      // Mesmo calendário: a data continua.
      expect(find.textContaining('20:00'), findsOneWidget);

      // Visitante: o calendário do adversário; a data de antes sai.
      await tapVisible(find.text('Visitante'));
      expect(
        find.text('Horários livres no calendário do Real Bairro'),
        findsOneWidget,
      );
      expect(find.textContaining('20:00'), findsNothing);
      await tapVisible(find.widgetWithText(InputDecorator, 'Data e hora'));
      expect(availability.freeSlotRequests.last, 'team-rival');
      await tapVisible(find.text('15:00'));
      expect(find.textContaining('15:00'), findsOneWidget);
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

      // Visitante sem adversário: o horário ainda não pode ser escolhido.
      await tester.ensureVisible(find.text('Visitante'));
      await tester.tap(find.text('Visitante'));
      await tester.pumpAndSettle();
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
      expect(games.created.single.hostIsHome, isFalse);
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
          of: find.byType(BottomSheet),
          matching: find.text('Arena Society Central'),
        ),
      );
      expect(venues.created, isEmpty);
      expect(find.text('Início'), findsOneWidget);
    });

    testWidgets('o local cadastrado vira o local do time ativo', (
      tester,
    ) async {
      final teams = FakeTeamRepository([teamA]);
      final venues = FakeVenueRepository();
      final container = await _container(teams: teams, venues: venues);
      await _pumpPage(tester, container, const VenueFormPage());

      // Sem local, a opção já vem marcada.
      expect(find.text('Local do Amigos FC'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await fillAddress(tester, 'Ginásio Municipal');
      await tapVisible(tester, find.text('Cadastrar local'));

      final linked = teams.updated.single;
      expect(linked.id, 'team-a');
      expect(linked.homeVenue?.id, venues.venues.single.id);
      expect(linked.toMap()['home_venue_id'], venues.venues.single.id);
    });

    testWidgets('pelo formulário do time não oferece vincular', (tester) async {
      final container = await _container(
        teams: FakeTeamRepository([teamA]),
        venues: FakeVenueRepository(),
      );
      await _pumpPage(
        tester,
        container,
        const VenueFormPage(offerTeamLink: false),
      );
      expect(find.byType(SwitchListTile), findsNothing);
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
