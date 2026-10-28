import 'package:flutter/material.dart';

import '../../games/domain/player_stats.dart';
import '../../teams/presentation/team_stats_widgets.dart';

/// Jogos, gols, assistências, cartões e craque, em duas linhas (Meus números
/// do Início do jogador).
class PlayerTotalsGrid extends StatelessWidget {
  const PlayerTotalsGrid({super.key, required this.totals});

  final AthleteTotals totals;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            StatTile(value: '${totals.games}', label: 'Jogos'),
            StatTile(
              value: '${totals.goals}',
              label: 'Gols',
              color: colors.primary,
            ),
            StatTile(
              value: '${totals.assists}',
              label: 'Assist.',
              tooltip: 'Assistências',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            StatTile(value: '${totals.yellowCards}', label: 'Amarelos'),
            StatTile(
              value: '${totals.redCards}',
              label: 'Vermelhos',
              color: colors.error,
            ),
            StatTile(
              value: '${totals.bestPlayer}',
              label: 'Craque',
              tooltip: 'Vezes em que foi o craque do jogo',
            ),
          ],
        ),
      ],
    );
  }
}
