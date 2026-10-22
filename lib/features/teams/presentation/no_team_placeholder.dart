import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/empty_state.dart';

/// Mostrado enquanto o administrador ainda não criou nenhum time.
class NoTeamPlaceholder extends StatelessWidget {
  const NoTeamPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
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
