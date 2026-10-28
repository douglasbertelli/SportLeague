import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../games/data/dispute_repository.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/game.dart';
import '../../invites/data/invite_repository.dart';
import '../../profile/domain/profile.dart';
import '../../teams/data/team_repository.dart';
import 'team_dashboard.dart';

/// Boas-vindas, o que está pendente (pedidos e convites), o painel do time
/// ativo e as ações de cada tipo de perfil. Puxar para baixo, ou voltar ao
/// app, busca as pendências de novo.
class HomeOverview extends ConsumerStatefulWidget {
  const HomeOverview({super.key, required this.profile, this.onOpenGames});

  final Profile profile;

  /// Leva à aba Jogos (pendências do dashboard).
  final ValueChanged<GameStage>? onOpenGames;

  @override
  ConsumerState<HomeOverview> createState() => _HomeOverviewState();
}

class _HomeOverviewState extends ConsumerState<HomeOverview> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Pedidos, convites e jogos podem ter mudado em outro aparelho.
  Future<void> _refresh() async {
    ref.invalidate(myInvitesProvider);
    if (ref.read(selectedTeamProvider).value?.id case final teamId?) {
      ref
        ..invalidate(teamRequestsProvider(teamId))
        ..invalidate(teamGamesProvider(teamId))
        ..invalidate(teamDisputesProvider(teamId));
    }
    await ref.read(myInvitesProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final onOpenGames = widget.onOpenGames;
    final theme = Theme.of(context);
    final actions = profile.isAdmin
        ? [
            _ActionTile(
              icon: Icons.shield_outlined,
              title: 'Meus times',
              subtitle: switch (ref.watch(myTeamsProvider).value?.length) {
                null => null,
                0 => 'Crie seu primeiro time',
                1 => '1 time',
                final count => '$count times',
              },
              onTap: () => context.push(Routes.teams),
            ),
            // Só faz sentido com um time ativo, cujo calendário é editado.
            if (ref.watch(selectedTeamProvider).value case final team?)
              _ActionTile(
                icon: Icons.event_available,
                title: 'Disponibilidade',
                subtitle: 'Dias e horários em que o ${team.name} joga',
                onTap: () => context.push(Routes.availability),
              ),
            _ActionTile(
              icon: Icons.place_outlined,
              title: 'Locais',
              subtitle: 'Quadras e campos onde as partidas acontecem',
              onTap: () => context.push(Routes.venues),
            ),
            _ActionTile(
              icon: Icons.mail_outline,
              title: 'Convites',
              subtitle: 'Código para os jogadores e pedidos para entrar',
              onTap: () => context.push(Routes.teamInvites),
            ),
          ]
        : [
            _ActionTile(
              icon: Icons.search,
              title: 'Buscar times',
              subtitle: 'Veja os times e peça para entrar',
              onTap: () => context.push(Routes.teamSearch),
            ),
            _ActionTile(
              icon: Icons.mail_outline,
              title: profile.isCoach
                  ? 'Meus times e convites'
                  : 'Meus convites',
              subtitle: switch ((ref.watch(myInvitesProvider).value ?? const [])
                  .where((invite) => invite.isPending && !invite.isRequest)
                  .length) {
                0 => 'Entrar com código, seus times e pedidos',
                1 => '1 convite para responder',
                final count => '$count convites para responder',
              },
              onTap: () => context.push(Routes.playerInvites),
            ),
          ];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // O jogador já tem a foto e o nome no topo.
          if (!profile.isPlayer) ...[
            Text(
              'Olá, ${profile.fullName.split(' ').first}!',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
          ],
          // O que espera resposta vem antes de tudo.
          _PendingCards(profile: profile),
          // Todos veem o painel do time ativo antes dos atalhos (o jogador, do
          // time em que é atleta, só acompanhando).
          if (profile.hasTeamHome || profile.isPlayer) ...[
            TeamDashboard(onOpenGames: onOpenGames),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Atalhos', style: theme.textTheme.titleMedium),
            ),
          ],
          ...actions,
        ],
      ),
    );
  }
}

/// Cards do que está pendente. O administrador vê os pedidos para entrar no
/// time ativo (de jogadores e técnicos); o jogador e o técnico, os convites
/// de times para responder e os pedidos que ainda esperam o time.
class _PendingCards extends ConsumerWidget {
  const _PendingCards({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = <Widget>[];

    if (profile.isAdmin) {
      final team = ref.watch(selectedTeamProvider).value;
      if (team != null && ref.watch(canManageTeamProvider)) {
        final requests = [
          for (final invite
              in ref.watch(teamRequestsProvider(team.id!)).value ?? const [])
            if (invite.isPending) invite,
        ];
        if (requests.isNotEmpty) {
          cards.add(
            _PendingCard(
              icon: Icons.person_add_alt_1_outlined,
              count: requests.length,
              title: requests.length == 1
                  ? '1 pedido para entrar no ${team.name}'
                  : '${requests.length} pedidos para entrar no ${team.name}',
              subtitle: _names([
                for (final invite in requests)
                  invite.isCoach
                      ? '${invite.playerName ?? 'Técnico'} (técnico)'
                      : invite.playerName ?? 'Jogador',
              ]),
              onTap: () => context.push(Routes.teamInvites),
            ),
          );
        }
      }
    } else {
      final invites = ref.watch(myInvitesProvider).value ?? const [];
      final toAnswer = [
        for (final invite in invites)
          if (invite.isPending && !invite.isRequest) invite,
      ];
      final waiting = [
        for (final invite in invites)
          if (invite.isPending && invite.isRequest) invite,
      ];
      if (toAnswer.isNotEmpty) {
        cards.add(
          _PendingCard(
            icon: Icons.mark_email_unread_outlined,
            count: toAnswer.length,
            title: toAnswer.length == 1
                ? '1 convite de time para responder'
                : '${toAnswer.length} convites de times para responder',
            subtitle: _names([
              for (final invite in toAnswer) invite.teamName ?? 'Time',
            ]),
            onTap: () => context.push(Routes.playerInvites),
          ),
        );
      }
      if (waiting.isNotEmpty) {
        cards.add(
          _PendingCard(
            icon: Icons.hourglass_top,
            title: waiting.length == 1
                ? 'Pedido para entrar no ${waiting.single.teamName ?? 'time'}'
                : '${waiting.length} pedidos para entrar em times',
            subtitle: waiting.length == 1
                ? 'Aguardando a resposta do time'
                : 'Aguardando: ${_names([for (final invite in waiting) invite.teamName ?? 'Time'])}',
            onTap: () => context.push(Routes.playerInvites),
          ),
        );
      }
    }

    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cards,
      ),
    );
  }

  /// "Bruno, Caio e Tite"; mais de três viram "e mais N".
  static String _names(List<String> names) {
    if (names.length <= 3) {
      return switch (names) {
        [final one] => one,
        _ => '${names.take(names.length - 1).join(', ')} e ${names.last}',
      };
    }
    return '${names.take(2).join(', ')} e mais ${names.length - 2}';
  }
}

/// Card de pendência, em destaque (cor do time), que leva ao lugar de
/// responder.
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Número no selo do ícone (o que precisa de ação).
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = this.count;
    return Card(
      color: colors.primaryContainer,
      child: ListTile(
        leading: Badge(
          label: count == null ? null : Text('$count'),
          isLabelVisible: count != null,
          child: Icon(icon, color: colors.onPrimaryContainer),
        ),
        title: Text(title, style: TextStyle(color: colors.onPrimaryContainer)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: colors.onPrimaryContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: colors.onPrimaryContainer),
        onTap: onTap,
      ),
    );
  }
}

/// Ação da home; sem [onTap] aparece desabilitada como "Em breve".
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = onTap == null ? 'Em breve' : this.subtitle;
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}
