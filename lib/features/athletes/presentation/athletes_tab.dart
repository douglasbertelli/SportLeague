import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

/// Aba Atletas do administrador. Cadastro e convites de jogadores: próxima
/// etapa.
class AthletesTab extends StatelessWidget {
  const AthletesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.groups,
      title: 'Nenhum atleta ainda',
      message:
          'Em breve você vai cadastrar e convidar os atletas dos seus times '
          'por aqui.',
    );
  }
}
