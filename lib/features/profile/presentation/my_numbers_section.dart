import 'package:flutter/material.dart';

import '../../games/domain/player_stats.dart';
import '../../sports/domain/sport_rules.dart';
import '../../teams/presentation/team_stats_widgets.dart';

/// Jogos, as estatísticas da súmula do esporte e o craque, de três em três
/// por linha (Meus números do Início do jogador e perfil do atleta).
class PlayerTotalsGrid extends StatelessWidget {
  const PlayerTotalsGrid({
    super.key,
    required this.totals,
    this.rules = footballRules,
  });

  final AthleteTotals totals;
  final SportRules rules;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tiles = [
      StatTile(value: '${totals.games}', label: 'Jogos'),
      for (final stat in rules.stats)
        StatTile(
          value: '${totals.value(stat.key)}',
          label: stat.totalsLabel,
          tooltip: stat.totalsTooltip,
          color: switch (stat.emphasis) {
            StatEmphasis.none => null,
            StatEmphasis.primary => colors.primary,
            StatEmphasis.error => colors.error,
          },
        ),
      StatTile(
        value: '${totals.bestPlayer}',
        label: 'Craque',
        tooltip: 'Vezes em que foi o craque do jogo',
      ),
    ];
    return Column(
      children: [
        for (var start = 0; start < tiles.length; start += 3) ...[
          if (start > 0) const SizedBox(height: 16),
          Row(children: tiles.skip(start).take(3).toList()),
        ],
      ],
    );
  }
}
