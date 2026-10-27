import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/core/theme/app_theme.dart';
import 'package:sport_league/features/athletes/data/athlete_repository.dart';
import 'package:sport_league/features/invites/data/invite_repository.dart';
import 'package:sport_league/features/invites/domain/team_invite.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/invites/presentation/invite_player_page.dart';
import 'package:sport_league/features/invites/presentation/player_invites_page.dart';
import 'package:sport_league/features/invites/presentation/team_invites_page.dart';
import 'package:sport_league/features/profile/data/profile_repository.dart';
import 'package:sport_league/features/profile/domain/profile.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';
import 'package:sport_league/features/teams/presentation/team_profile_page.dart';

import '../teams/fakes.dart';

/// Convites e pedidos guardados em memória, como o banco.
class FakeInviteRepository implements InviteRepository {
  FakeInviteRepository({
    this.codes = const {},
    List<TeamInvite> invites = const [],
    this.playerTeams = const [],
  }) : invites = [...invites];

  final Map<String, String> codes;
  final List<TeamInvite> invites;
  final List<Team> playerTeams;
  final responses = <(String, bool)>[];
  final canceled = <String>[];
  final requests = <(String, String)>[];
  final joined = <String>[];
  var regenerated = 0;

  /// Técnicos por time.
  final coaches = <String, List<PlayerSummary>>{};

  @override
  Future<List<PlayerSummary>> teamCoaches(String teamId) async =>
      coaches[teamId] ?? const [];

  @override
  Future<void> removeCoach(String teamId, String profileId) async =>
      coaches[teamId]?.removeWhere((coach) => coach.id == profileId);

  @override
  Future<String?> inviteCode(String teamId) async => codes[teamId];

  @override
  Future<String> regenerateCode(String teamId) async {
    regenerated++;
    return codes[teamId]!;
  }

  @override
  Future<List<TeamInvite>> teamRequests(String teamId) async => [
    for (final invite in invites)
      if (invite.teamId == teamId && invite.isRequest) invite,
  ];

  @override
  Future<List<TeamInvite>> teamSentInvites(String teamId) async => [
    for (final invite in invites)
      if (invite.teamId == teamId && !invite.isRequest) invite,
  ];

  List<PlayerSummary> players = const [];
  final sentInvites = <(String, String)>[];

  @override
  Future<List<PlayerSummary>> searchPlayers(String query) async => [
    for (final player in players)
      if (player.name.toLowerCase().contains(query.trim().toLowerCase()))
        player,
  ];

  @override
  Future<void> invitePlayer({
    required String teamId,
    required String profileId,
    required String ownerId,
  }) async {
    sentInvites.add((teamId, profileId));
    invites.add(
      TeamInvite(
        id: 'i${invites.length + 1}',
        teamId: teamId,
        profileId: profileId,
        isRequest: false,
        status: InviteStatus.pending,
        createdAt: DateTime(2026, 10, 24),
        playerName: players.firstWhere((p) => p.id == profileId).name,
      ),
    );
  }

  @override
  Future<List<TeamInvite>> myInvites(String profileId) async => [
    for (final invite in invites)
      if (invite.profileId == profileId) invite,
  ];

  @override
  Future<List<Team>> myTeams(String profileId) async => playerTeams;

  @override
  Future<void> respond(String inviteId, {required bool accept}) async =>
      responses.add((inviteId, accept));

  @override
  Future<void> cancel(String inviteId) async => canceled.add(inviteId);

  @override
  Future<void> requestToJoin(String teamId, String profileId) async {
    requests.add((teamId, profileId));
    invites.add(
      TeamInvite(
        id: 'r${invites.length + 1}',
        teamId: teamId,
        profileId: profileId,
        isRequest: true,
        status: InviteStatus.pending,
        createdAt: DateTime(2026, 10, 24),
      ),
    );
  }

  @override
  Future<String?> teamIdByCode(String code) async => codes.entries
      .where((entry) => entry.value == code)
      .map((entry) => entry.key)
      .firstOrNull;

  @override
  Future<String> joinWithCode(String code) async {
    joined.add(code);
    return (await teamIdByCode(code))!;
  }
}

const _rival = Team(
  id: 'team-rival',
  ownerId: 'u2',
  name: 'Real Bairro',
  modalities: {Modality.society},
);

Future<ProviderContainer> _container({
  required UserRole role,
  required FakeInviteRepository invites,
  List<String>? shared,
  FakeAthleteRepository? athletes,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      currentUserIdProvider.overrideWithValue('u1'),
      currentProfileProvider.overrideWithValue(
        AsyncData(
          Profile(
            id: 'u1',
            fullName: 'Ana Souza',
            role: role,
            plan: SubscriptionPlan.free,
          ),
        ),
      ),
      teamRepositoryProvider.overrideWithValue(
        FakeTeamRepository([if (role == UserRole.admin) teamA, _rival]),
      ),
      athleteRepositoryProvider.overrideWithValue(
        athletes ?? FakeAthleteRepository({}),
      ),
      inviteRepositoryProvider.overrideWithValue(invites),
      shareTextProvider.overrideWithValue((text) async => shared?.add(text)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container,
  Widget page,
) async {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Início')),
        routes: [GoRoute(path: 'page', builder: (_, _) => page)],
      ),
      GoRoute(
        path: Routes.teamProfile,
        builder: (_, state) => TeamProfilePage(teamId: state.extra as String),
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

TeamInvite _request(
  String id, {
  String teamId = 'team-a',
  String profileId = 'u9',
  InviteStatus status = InviteStatus.pending,
  String playerName = 'Carlos Lima',
}) => TeamInvite(
  id: id,
  teamId: teamId,
  profileId: profileId,
  isRequest: true,
  status: status,
  createdAt: DateTime(2026, 10, 20),
  playerName: playerName,
  teamName: teamId == 'team-rival' ? 'Real Bairro' : 'Amigos FC',
);

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('convite vem do banco com o jogador e o time', () {
    final invite = TeamInvite.fromMap({
      'id': 'i1',
      'team_id': 'team-a',
      'profile_id': 'u9',
      'direction': 'request',
      'status': 'accepted',
      'created_at': '2026-10-20T12:00:00+00:00',
      'responded_at': '2026-10-21T12:00:00+00:00',
      'player': {'full_name': 'Carlos Lima', 'avatar_url': null},
      'team': {'name': 'Amigos FC', 'logo_url': null},
    });
    expect(invite.isRequest, isTrue);
    expect(invite.status, InviteStatus.accepted);
    expect(invite.isPending, isFalse);
    expect(invite.playerName, 'Carlos Lima');
    expect(invite.teamName, 'Amigos FC');
    expect(invite.respondedAt, isNotNull);
  });

  testWidgets('admin compartilha o código e responde os pedidos', (
    tester,
  ) async {
    final shared = <String>[];
    final invites = FakeInviteRepository(
      codes: {'team-a': 'ABCD2345'},
      invites: [
        _request('r1'),
        _request('r2', playerName: 'Bia Rocha'),
        _request('r3', status: InviteStatus.accepted, playerName: 'Duda'),
      ],
    );
    final container = await _container(
      role: UserRole.admin,
      invites: invites,
      shared: shared,
    );
    await _pumpPage(tester, container, const TeamInvitesPage());

    expect(find.text('ABCD2345'), findsOneWidget);
    await tester.tap(find.text('Compartilhar'));
    await tester.pump();
    expect(shared.single, contains('ABCD2345'));
    expect(shared.single, contains('Amigos FC'));

    await tester.tap(find.text('Gerar outro'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Gerar outro'),
      ),
    );
    await tester.pumpAndSettle();
    expect(invites.regenerated, 1);

    // Pendentes com Aceitar/Recusar; o aceito vai para o histórico.
    expect(find.text('Pedidos para entrar (2)'), findsOneWidget);
    expect(find.text('Duda'), findsOneWidget);
    expect(find.text('Aceito · 20/10/2026'), findsOneWidget);
    await tester.tap(find.text('Aceitar').first);
    await tester.pumpAndSettle();
    expect(invites.responses, [('r1', true)]);

    await tester.ensureVisible(find.text('Recusar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recusar').last);
    await tester.pumpAndSettle();
    expect(find.text('Recusar pedido?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Recusar'),
      ),
    );
    await tester.pumpAndSettle();
    expect(invites.responses.last, ('r2', false));
  });

  testWidgets('jogador entra no time com o código', (tester) async {
    final invites = FakeInviteRepository(
      codes: {'team-rival': 'WXYZ7890'},
      invites: [_request('r1', teamId: 'team-rival', profileId: 'u1')],
    );
    final container = await _container(role: UserRole.player, invites: invites);
    await _pumpPage(tester, container, const PlayerInvitesPage());

    // Código errado.
    await tester.enterText(find.byType(TextField), 'nada1234');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Código não encontrado. Confira com o time.'),
      findsOneWidget,
    );
    expect(invites.joined, isEmpty);

    // Código certo (em minúsculas): mostra o time antes de entrar.
    await tester.enterText(find.byType(TextField), 'wxyz7890');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Entrar no time?'), findsOneWidget);
    expect(find.text('Real Bairro'), findsWidgets);
    await tester.tap(find.text('Entrar no time'));
    await tester.pumpAndSettle();
    expect(invites.joined, ['WXYZ7890']);
    expect(find.text('Você entrou no Real Bairro!'), findsOneWidget);

    // O pedido pendente pode ser cancelado.
    expect(find.text('Seu pedido · Aguardando · 20/10/2026'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar pedido'));
    await tester.pumpAndSettle();
    expect(invites.canceled, ['r1']);
  });

  testWidgets('admin convida jogadores do app pelo nome', (tester) async {
    final invites = FakeInviteRepository(codes: {'team-a': 'ABCD2345'})
      ..players = const [
        PlayerSummary(id: 'u7', name: 'Carlos Lima'),
        PlayerSummary(id: 'u8', name: 'Bia Rocha'),
        PlayerSummary(id: 'u9', name: 'Caio Souza'),
      ];
    // Caio já é atleta do time.
    final container = await _container(
      role: UserRole.admin,
      invites: invites,
      athletes: FakeAthleteRepository({
        'team-a': [
          const Athlete(teamId: 'team-a', name: 'Caio Souza', profileId: 'u9'),
        ],
      }),
    );
    await _pumpPage(tester, container, const InvitePlayerPage());

    await tester.enterText(find.byType(TextField), 'ca');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Carlos Lima'), findsOneWidget);
    expect(find.text('Caio Souza'), findsOneWidget);
    expect(find.text('Bia Rocha'), findsNothing);

    await tester.tap(find.text('Convidar').first);
    await tester.pumpAndSettle();
    expect(invites.sentInvites, [('team-a', 'u7')]);
    // Convidado e já atleta: o botão vira o selo.
    expect(find.text('Convidado'), findsOneWidget);
    expect(find.text('No time'), findsOneWidget);
    expect(find.text('Convidar'), findsNothing);
  });

  testWidgets('jogador aceita ou recusa um convite recebido', (tester) async {
    final invites = FakeInviteRepository(
      invites: [
        TeamInvite(
          id: 'i1',
          teamId: 'team-rival',
          profileId: 'u1',
          isRequest: false,
          status: InviteStatus.pending,
          createdAt: DateTime(2026, 10, 22),
          teamName: 'Real Bairro',
        ),
        TeamInvite(
          id: 'i2',
          teamId: 'team-b',
          profileId: 'u1',
          isRequest: false,
          status: InviteStatus.pending,
          createdAt: DateTime(2026, 10, 23),
          teamName: 'Bola Murcha',
        ),
      ],
    );
    final container = await _container(role: UserRole.player, invites: invites);
    await _pumpPage(tester, container, const PlayerInvitesPage());

    expect(find.text('Convidou você em 22/10/2026'), findsOneWidget);
    await tester.ensureVisible(find.text('Aceitar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aceitar').first);
    await tester.pumpAndSettle();
    expect(invites.responses, [('i1', true)]);
    expect(find.text('Você entrou no Real Bairro!'), findsOneWidget);

    await tester.ensureVisible(find.text('Recusar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recusar').last);
    await tester.pumpAndSettle();
    expect(find.text('Recusar convite?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Recusar'),
      ),
    );
    await tester.pumpAndSettle();
    expect(invites.responses.last, ('i2', false));
  });

  testWidgets('jogador pede para entrar pelo perfil do time', (tester) async {
    final invites = FakeInviteRepository();
    final container = await _container(role: UserRole.player, invites: invites);
    await _pumpPage(
      tester,
      container,
      const TeamProfilePage(teamId: 'team-rival'),
    );

    expect(find.text('Seguir'), findsNothing);
    await tester.tap(find.text('Pedir para entrar'));
    await tester.pumpAndSettle();
    expect(invites.requests, [('team-rival', 'u1')]);
    expect(find.text('Pedido enviado'), findsOneWidget);
  });

  testWidgets('o perfil do time mostra o técnico', (tester) async {
    final invites = FakeInviteRepository();
    final container = await _container(role: UserRole.player, invites: invites);
    await _pumpPage(
      tester,
      container,
      const TeamProfilePage(teamId: 'team-rival'),
    );
    // Sem técnico, a seção não aparece.
    expect(find.text('Comissão técnica'), findsNothing);
    expect(find.text('Técnico'), findsNothing);

    invites.coaches['team-rival'] = [
      const PlayerSummary(id: 'u5', name: 'Tite Bacchi'),
    ];
    container.invalidate(teamCoachesProvider('team-rival'));
    await tester.pumpAndSettle();
    expect(find.text('Tite Bacchi'), findsOneWidget);
    expect(find.text('Técnico'), findsNWidgets(2));
  });

  testWidgets('no time em que já é atleta, o jogador vê que é do time', (
    tester,
  ) async {
    final container = await _container(
      role: UserRole.player,
      invites: FakeInviteRepository(playerTeams: const [_rival]),
    );
    await _pumpPage(
      tester,
      container,
      const TeamProfilePage(teamId: 'team-rival'),
    );
    expect(find.text('Você é do time'), findsOneWidget);
    expect(find.text('Pedir para entrar'), findsNothing);
  });
}
