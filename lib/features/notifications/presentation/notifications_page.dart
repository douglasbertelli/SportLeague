import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../games/data/games_tab_request.dart';
import '../../games/domain/game.dart';
import '../../games/presentation/presence.dart';
import '../../profile/data/profile_repository.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';

/// Sino do topo (todos os perfis) com o número de não lidas; abre a central.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      tooltip: unread == 0
          ? 'Notificações'
          : 'Notificações, $unread não ${unread == 1 ? 'lida' : 'lidas'}',
      onPressed: () => context.push(Routes.notifications),
      icon: Badge(
        label: Text(unread > 99 ? '99+' : '$unread'),
        isLabelVisible: unread > 0,
        child: Icon(
          unread > 0 ? Icons.notifications : Icons.notifications_none,
        ),
      ),
    );
  }
}

/// Central de notificações: as mais novas primeiro, as não lidas em
/// destaque. Separada por time, como o resto do app: mostra as do time ativo
/// (e as de times de que o usuário não faz parte, como um convite); quem tem
/// mais de um time troca pelos chips, que mostram as não lidas de cada um.
/// Tocar marca como lida e leva ao lugar de responder; arrastar para o lado
/// apaga.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _markAllRead(
    BuildContext context,
    WidgetRef ref,
    List<AppNotification> shown,
  ) async {
    final ids = [
      for (final notification in shown)
        if (!notification.isRead) notification.id,
    ];
    if (ids.isEmpty) return;
    try {
      await ref.read(notificationRepositoryProvider).markManyRead(ids);
    } catch (error) {
      if (context.mounted) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    }
  }

  /// Tira da lista na hora (o Dismissible exige) e apaga no banco; se der
  /// erro, ela volta.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    final deleted = ref.read(deletedNotificationsProvider.notifier)
      ..add(notification.id);
    try {
      await ref.read(notificationRepositoryProvider).delete(notification.id);
    } catch (error) {
      deleted.remove(notification.id);
      if (context.mounted) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    }
  }

  /// Onde ir a partir da notificação; nulo fica na central.
  NotificationAction? _actionFor(AppNotification notification, WidgetRef ref) {
    final isAdmin = ref.read(currentProfileProvider).value?.isAdmin ?? false;
    return switch (notification.kind) {
      'invite' => const NotificationAction.page(
        'Responder convite',
        Icons.mail_outline,
        Routes.playerInvites,
        needsAction: true,
      ),
      'request' when isAdmin => const NotificationAction.page(
        'Ver pedido',
        Icons.person_add_alt_1_outlined,
        Routes.teamInvites,
        needsAction: true,
      ),
      'game_invite' => const NotificationAction.games(
        'Responder amistoso',
        Icons.sports_soccer,
        GameStage.pending,
        needsAction: true,
      ),
      'dispute' => const NotificationAction.games(
        'Responder contestação',
        Icons.report_outlined,
        GameStage.played,
        needsAction: true,
      ),
      'game_score' => const NotificationAction.games(
        'Conferir placar',
        Icons.scoreboard_outlined,
        GameStage.played,
        needsAction: true,
      ),
      'invite_answer' when isAdmin => const NotificationAction.page(
        'Ver convites',
        Icons.mail_outline,
        Routes.teamInvites,
      ),
      'request_answer' => const NotificationAction.page(
        'Ver meus times',
        Icons.groups_outlined,
        Routes.playerInvites,
      ),
      'fundraiser' || 'fundraiser_paid' => const NotificationAction.page(
        'Ver vaquinha',
        Icons.savings_outlined,
        Routes.fundraisers,
      ),
      'game_accepted' ||
      'game_declined' ||
      'game_canceled' ||
      'game_rescheduled' ||
      'dispute_answer' when isAdmin => NotificationAction.games(
        'Ver amistoso',
        Icons.sports_soccer,
        switch (notification.kind) {
          'game_accepted' || 'game_rescheduled' => GameStage.scheduled,
          'dispute_answer' => GameStage.played,
          _ => GameStage.canceled,
        },
      ),
      _ => null,
    };
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    if (!notification.isRead) {
      // Marcar como lida não segura a navegação.
      ref
          .read(notificationRepositoryProvider)
          .markRead(notification.id)
          .ignore();
    }
    final action = _actionFor(notification, ref);
    if (action == null) return;
    // O time da notificação vira o time ativo (o administrador pode ter
    // vários): convites e jogos abrem no time certo.
    if (notification.teamId case final teamId?
        when ref.read(currentProfileProvider).value?.isAdmin ?? false) {
      await ref.read(selectedTeamIdProvider.notifier).select(teamId);
    }
    if (!context.mounted) return;
    switch (action) {
      case NotificationAction(:final route?):
        await context.push(route);
      case NotificationAction(:final stage?):
        // A aba Jogos, na aba de dentro certa (Pendentes, Realizados…).
        ref.read(gamesTabRequestProvider.notifier).open(stage);
        context.go(Routes.home);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(visibleNotificationsProvider);
    final teams = ref.watch(myTeamsProvider).value ?? const <Team>[];
    final activeId = ref.watch(selectedTeamProvider).value?.id;
    final teamIds = {for (final team in teams) team.id};
    // Do time ativo, ou de um time de que o usuário não faz parte (convite,
    // pedido respondido) e sem time.
    bool belongsHere(AppNotification notification) =>
        notification.teamId == activeId ||
        notification.teamId == null ||
        !teamIds.contains(notification.teamId);
    final shown = [
      for (final notification in all ?? const <AppNotification>[])
        if (belongsHere(notification)) notification,
    ];
    final unreadShown = shown.where((notification) => !notification.isRead);
    int unreadOf(String teamId) => (all ?? const <AppNotification>[])
        .where((n) => n.teamId == teamId && !n.isRead)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (unreadShown.isNotEmpty)
            IconButton(
              tooltip: 'Marcar todas como lidas',
              icon: const Icon(Icons.done_all),
              onPressed: () => _markAllRead(context, ref, shown),
            ),
        ],
      ),
      body: switch (ref.watch(myNotificationsProvider)) {
        AsyncValue(hasError: true, hasValue: false) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(myNotificationsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar. Tentar novamente'),
          ),
        ),
        AsyncValue(hasValue: false) => const Center(
          child: CircularProgressIndicator(),
        ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Um chip por time (o ativo marcado), com as não lidas de cada um.
            if (teams.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    for (final team in teams)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: TeamLogo(team: team, radius: 12),
                          label: Badge(
                            label: Text('${unreadOf(team.id!)}'),
                            isLabelVisible:
                                team.id != activeId && unreadOf(team.id!) > 0,
                            offset: const Offset(14, -6),
                            child: Text(team.name),
                          ),
                          selected: team.id == activeId,
                          onSelected: (_) => ref
                              .read(selectedTeamIdProvider.notifier)
                              .select(team.id!),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: shown.isEmpty
                  ? const EmptyState(
                      icon: Icons.notifications_none,
                      title: 'Nenhuma notificação',
                      message:
                          'Convites, pedidos, amistosos, placares e vaquinhas '
                          'aparecem aqui.',
                    )
                  : _list(context, ref, shown),
            ),
          ],
        ),
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<AppNotification> notifications,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
    children: [
      for (final notification in notifications)
        Dismissible(
          key: ValueKey(notification.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: Theme.of(context).colorScheme.errorContainer,
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) => _delete(context, ref, notification),
          child: _NotificationTile(
            notification: notification,
            action: _actionFor(notification, ref),
            onTap: () => _open(context, ref, notification),
            // O pedido de presença se responde no próprio card.
            extra: switch (notification) {
              AppNotification(
                kind: 'presence',
                :final gameId?,
                :final teamId?,
              ) =>
                PresenceButtons(
                  gameId: gameId,
                  teamId: teamId,
                  onAnswered: () {
                    if (!notification.isRead) {
                      ref
                          .read(notificationRepositoryProvider)
                          .markRead(notification.id)
                          .ignore();
                    }
                  },
                ),
              _ => null,
            },
          ),
        ),
    ],
  );
}

/// Para onde a notificação leva: uma página ([route]) ou a aba Jogos numa aba
/// de dentro ([stage]). Com [needsAction], o card mostra o botão (o usuário
/// tem algo a responder lá).
class NotificationAction {
  const NotificationAction.page(
    this.label,
    this.icon,
    String this.route, {
    this.needsAction = false,
  }) : stage = null;

  const NotificationAction.games(
    this.label,
    this.icon,
    GameStage this.stage, {
    this.needsAction = false,
  }) : route = null;

  final String label;
  final IconData icon;
  final String? route;
  final GameStage? stage;
  final bool needsAction;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.action,
    required this.onTap,
    this.extra,
  });

  final AppNotification notification;
  final NotificationAction? action;
  final VoidCallback onTap;

  /// Embaixo do texto, no lugar do botão (ex.: Vou / Não vou).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = !notification.isRead;
    final action = this.action;
    final extra = this.extra;
    final tile = ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: unread
            ? colors.primary
            : colors.surfaceContainerHighest,
        foregroundColor: unread ? colors.onPrimary : colors.onSurfaceVariant,
        child: Icon(notification.icon, size: 20),
      ),
      title: Text(
        notification.title,
        style: TextStyle(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
          color: unread ? colors.onPrimaryContainer : null,
        ),
      ),
      subtitle: Text(
        '${notification.body}\n${timeAgo(notification.createdAt)}',
        style: TextStyle(
          color: unread ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        ),
      ),
      isThreeLine: true,
      trailing: unread
          ? Semantics(
              label: 'Não lida',
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );

    return Card(
      color: unread ? colors.primaryContainer : null,
      child: extra != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile,
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                  child: Align(alignment: Alignment.centerLeft, child: extra),
                ),
              ],
            )
          : action == null || !action.needsAction
          ? tile
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile,
                // O botão leva direto ao lugar de responder.
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: onTap,
                      icon: Icon(action.icon, size: 18),
                      label: Text(action.label),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
