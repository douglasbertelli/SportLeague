import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sport_league/core/router/routes.dart';
import 'package:sport_league/core/storage/preferences_provider.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/games/data/games_tab_request.dart';
import 'package:sport_league/features/games/data/presence_repository.dart';
import 'package:sport_league/features/games/domain/presence_answer.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';
import 'package:sport_league/features/notifications/data/notification_repository.dart';
import 'package:sport_league/features/notifications/domain/app_notification.dart';
import 'package:sport_league/features/notifications/presentation/notifications_page.dart';
import 'package:sport_league/features/profile/data/profile_repository.dart';
import 'package:sport_league/features/profile/domain/profile.dart';

import '../games/fake_presence.dart';

class _FakeNotificationRepository implements NotificationRepository {
  final read = <String>[];
  final deleted = <String>[];
  var allRead = 0;

  @override
  Future<void> markRead(String id) async => read.add(id);

  @override
  Future<void> markAllRead(String userId) async => allRead++;

  /// Marcadas como lidas pelo "Marcar todas" (só as da tela).
  final manyRead = <String>[];

  @override
  Future<void> markManyRead(List<String> ids) async => manyRead.addAll(ids);

  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _notifications = [
  AppNotification(
    id: 'n1',
    kind: 'invite',
    title: 'Convite de time',
    body: 'Amigos FC convidou você para entrar no time.',
    createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  ),
  AppNotification(
    id: 'n2',
    kind: 'game_canceled',
    title: 'Amistoso cancelado',
    body: 'Real Bairro cancelou o amistoso de 07/11 às 15:00. Motivo: Chuva.',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    readAt: DateTime.now(),
  ),
];

typedef _Pumped = ({
  _FakeNotificationRepository repo,
  ProviderContainer container,
});

Future<_Pumped> _pump(
  WidgetTester tester, {
  List<AppNotification>? notifications,
  UserRole role = UserRole.player,
  List<Team> teams = const [],
  String? activeTeamId,
  FakePresenceRepository? presence,
}) async {
  SharedPreferences.setMockInitialValues({'selected_team_id': ?activeTeamId});
  final preferences = await SharedPreferences.getInstance();
  final repository = _FakeNotificationRepository();
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
      notificationRepositoryProvider.overrideWithValue(repository),
      presenceRepositoryProvider.overrideWithValue(
        presence ?? FakePresenceRepository(),
      ),
      // Os times do usuário (sem banco nos testes).
      myTeamsProvider.overrideWith((ref) async => teams),
      myNotificationsProvider.overrideWith(
        (ref) => Stream.value(notifications ?? _notifications),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Início')),
        routes: [
          GoRoute(path: 'page', builder: (_, _) => const NotificationsPage()),
        ],
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const Scaffold(body: Text('Home do app')),
      ),
      GoRoute(
        path: Routes.playerInvites,
        builder: (_, _) => const Scaffold(body: Text('Tela de convites')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push('/page');
  await tester.pumpAndSettle();
  return (repo: repository, container: container);
}

void main() {
  test('tempo relativo', () {
    final now = DateTime(2026, 10, 29, 12);
    expect(timeAgo(now, now), 'agora');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), 'há 5 min');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now), 'há 3 h');
    expect(timeAgo(now.subtract(const Duration(days: 1)), now), 'ontem');
    expect(timeAgo(now.subtract(const Duration(days: 4)), now), 'há 4 dias');
    expect(timeAgo(DateTime(2026, 9, 2), now), '02/09/2026');
  });

  testWidgets('lista as notificações, a não lida em destaque', (tester) async {
    await _pump(tester);
    expect(find.text('Convite de time'), findsOneWidget);
    expect(find.textContaining('Motivo: Chuva'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Não lida')), findsOneWidget);
    expect(find.byTooltip('Marcar todas como lidas'), findsOneWidget);
  });

  testWidgets('tocar marca como lida e leva aos convites', (tester) async {
    final repository = (await _pump(tester)).repo;
    await tester.tap(find.text('Convite de time'));
    await tester.pumpAndSettle();
    expect(repository.read, ['n1']);
    expect(find.text('Tela de convites'), findsOneWidget);
  });

  testWidgets('marcar todas como lidas e apagar arrastando', (tester) async {
    final repository = (await _pump(tester)).repo;
    await tester.tap(find.byTooltip('Marcar todas como lidas'));
    await tester.pumpAndSettle();
    // Só a não lida que está na tela.
    expect(repository.manyRead, ['n1']);

    await tester.drag(find.text('Amistoso cancelado'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(repository.deleted, ['n2']);
  });

  testWidgets('só o que pede ação tem botão', (tester) async {
    await _pump(tester);
    // O convite pede resposta; o amistoso cancelado é só aviso.
    expect(find.text('Responder convite'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ver amistoso'), findsNothing);
  });

  testWidgets('o botão do convite de amistoso abre Jogos › Pendentes do time', (
    tester,
  ) async {
    final pumped = await _pump(
      tester,
      role: UserRole.admin,
      notifications: [
        AppNotification(
          id: 'n3',
          kind: 'game_invite',
          title: 'Convite de amistoso',
          body: 'Real Bairro quer marcar um amistoso em 07/11 às 15:00.',
          createdAt: DateTime.now(),
          teamId: 'team-b',
          gameId: 'g9',
        ),
      ],
    );
    await tester.tap(find.text('Responder amistoso'));
    await tester.pumpAndSettle();
    expect(pumped.repo.read, ['n3']);
    // O time do convite vira o ativo e a aba Jogos abre em Pendentes.
    expect(pumped.container.read(selectedTeamIdProvider), 'team-b');
    expect(
      pumped.container.read(gamesTabRequestProvider)?.stage,
      GameStage.pending,
    );
    expect(find.text('Home do app'), findsOneWidget);
  });

  testWidgets('cada time vê as suas notificações', (tester) async {
    AppNotification note(String id, String team, String title) =>
        AppNotification(
          id: id,
          kind: 'game_accepted',
          title: title,
          body: '…',
          createdAt: DateTime.now(),
          teamId: team,
        );
    final pumped = await _pump(
      tester,
      role: UserRole.admin,
      teams: const [
        Team(id: 'team-a', ownerId: 'u1', name: 'Amigos FC', modalities: {}),
        Team(id: 'team-b', ownerId: 'u1', name: 'Bola Murcha', modalities: {}),
      ],
      activeTeamId: 'team-a',
      notifications: [
        note('a1', 'team-a', 'Aviso do Amigos'),
        note('b1', 'team-b', 'Aviso do Bola Murcha'),
        // De um time de fora (ex.: convite): aparece em qualquer time.
        note('x1', 'team-x', 'Aviso de fora'),
      ],
    );
    expect(find.text('Aviso do Amigos'), findsOneWidget);
    expect(find.text('Aviso de fora'), findsOneWidget);
    expect(find.text('Aviso do Bola Murcha'), findsNothing);

    // O chip do outro time mostra a não lida e troca o time ativo.
    await tester.tap(find.text('Bola Murcha'));
    await tester.pumpAndSettle();
    expect(pumped.container.read(selectedTeamIdProvider), 'team-b');
    expect(find.text('Aviso do Bola Murcha'), findsOneWidget);
    expect(find.text('Aviso do Amigos'), findsNothing);

    // "Marcar todas" vale só para o que está na tela.
    await tester.tap(find.byTooltip('Marcar todas como lidas'));
    await tester.pumpAndSettle();
    expect(pumped.repo.manyRead, unorderedEquals(['b1', 'x1']));
  });

  testWidgets('apagada não volta ao trocar de time', (tester) async {
    AppNotification note(String id, String team, String title) =>
        AppNotification(
          id: id,
          kind: 'game_accepted',
          title: title,
          body: '…',
          createdAt: DateTime.now(),
          teamId: team,
        );
    // O stream não avisa do DELETE (como o ao vivo do Supabase).
    final pumped = await _pump(
      tester,
      role: UserRole.admin,
      teams: const [
        Team(id: 'team-a', ownerId: 'u1', name: 'Amigos FC', modalities: {}),
        Team(id: 'team-b', ownerId: 'u1', name: 'Bola Murcha', modalities: {}),
      ],
      activeTeamId: 'team-a',
      notifications: [
        note('a1', 'team-a', 'Aviso 1 do Amigos'),
        note('a2', 'team-a', 'Aviso 2 do Amigos'),
        note('b1', 'team-b', 'Aviso do Bola Murcha'),
      ],
    );
    await tester.drag(find.text('Aviso 1 do Amigos'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(pumped.repo.deleted, ['a1']);
    expect(find.text('Aviso 1 do Amigos'), findsNothing);

    await tester.tap(find.text('Bola Murcha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amigos FC'));
    await tester.pumpAndSettle();
    expect(find.text('Aviso 1 do Amigos'), findsNothing);
    expect(find.text('Aviso 2 do Amigos'), findsOneWidget);
    // Nem conta mais no sino.
    expect(pumped.container.read(unreadNotificationsProvider), 2);
  });

  testWidgets('pedido de presença se responde no card', (tester) async {
    final presence = FakePresenceRepository();
    final pumped = await _pump(
      tester,
      presence: presence,
      notifications: [
        AppNotification(
          id: 'p1',
          kind: 'presence',
          title: 'Confirme sua presença',
          body:
              'O Amigos FC joga contra Real Bairro em 07/11 às 15:00. '
              'Você vai?',
          createdAt: DateTime.now(),
          teamId: 'team-a',
          gameId: 'g1',
        ),
      ],
    );
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(presence.answers, [('g1', 'team-a', PresenceAnswer.yes)]);
    // Responder marca como lida.
    expect(pumped.repo.read, ['p1']);
  });

  testWidgets('sem notificações', (tester) async {
    await _pump(tester, notifications: const []);
    expect(find.text('Nenhuma notificação'), findsOneWidget);
    expect(find.byTooltip('Marcar todas como lidas'), findsNothing);
  });
}
