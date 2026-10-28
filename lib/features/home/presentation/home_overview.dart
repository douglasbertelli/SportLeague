import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../games/domain/game.dart';
import '../../invites/data/invite_repository.dart';
import '../../profile/domain/profile.dart';
import '../../teams/data/team_repository.dart';
import 'team_dashboard.dart';

/// Boas-vindas e as ações de cada tipo de perfil (o administrador vê também o
/// painel do time ativo).
class HomeOverview extends ConsumerWidget {
  const HomeOverview({super.key, required this.profile, this.onOpenGames});

  final Profile profile;

  /// Leva à aba Jogos (pendências do dashboard).
  final ValueChanged<GameStage>? onOpenGames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Olá, ${profile.fullName.split(' ').first}!',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
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
