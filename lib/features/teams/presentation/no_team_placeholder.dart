import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/team_repository.dart';

/// Mostrado enquanto o administrador ainda não criou nenhum time (ou o técnico
/// ou o jogador ainda não entrou em nenhum: eles não criam times, só se
/// vinculam).
class NoTeamPlaceholder extends ConsumerWidget {
  const NoTeamPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isCoachProvider) || ref.watch(isPlayerProvider)) {
      return EmptyState(
        icon: Icons.shield_outlined,
        title: 'Entre num time',
        message:
            'Use o código do time ou peça para entrar pelo perfil dele. Você '
            'pode acompanhar quantos times quiser.',
        action: FilledButton.icon(
          onPressed: () => context.push(Routes.playerInvites),
          icon: const Icon(Icons.login),
          label: const Text('Entrar num time'),
        ),
      );
    }
    return EmptyState(
      icon: Icons.shield_outlined,
      title: 'Crie seu primeiro time',
      message:
          'Os atletas e os jogos ficam separados por time. Você pode ter '
          'quantos times quiser.',
      action: FilledButton.icon(
        onPressed: () => context.push(Routes.newTeam),
        icon: const Icon(Icons.add),
        label: const Text('Criar time'),
      ),
    );
  }
}
