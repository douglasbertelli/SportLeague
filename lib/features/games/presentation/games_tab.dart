import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

/// Aba Jogos do administrador. Amistosos e campeonatos: próxima etapa.
class GamesTab extends StatelessWidget {
  const GamesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.sports_soccer,
      title: 'Nenhum jogo ainda',
      message:
          'Em breve você vai marcar amistosos e campeonatos para os seus times '
          'por aqui.',
    );
  }
}
