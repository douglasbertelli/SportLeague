import 'package:flutter/material.dart';

import '../domain/team_stats.dart';

/// Card com jogos, vitórias, empates, derrotas, gols e saldo (perfil e
/// dashboard).
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.stats});

  final TeamStats stats;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final difference = stats.goalDifference;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Row(
              children: [
                StatTile(value: '${stats.played}', label: 'Jogos'),
                StatTile(
                  value: '${stats.wins}',
                  label: 'Vitórias',
                  color: colors.primary,
                ),
                StatTile(value: '${stats.draws}', label: 'Empates'),
                StatTile(
                  value: '${stats.losses}',
                  label: 'Derrotas',
                  color: colors.error,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                StatTile(value: '${stats.goalsFor}', label: 'Gols pró'),
                StatTile(value: '${stats.goalsAgainst}', label: 'Gols contra'),
                StatTile(
                  value: difference > 0 ? '+$difference' : '$difference',
                  label: 'Saldo',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Número grande com o rótulo embaixo; ocupa uma parte igual da linha.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.color,
  });

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        container: true,
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// V (verde), E (cinza) ou D (vermelho); "–" sem placar.
class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge({super.key, required this.game, this.radius = 18});

  final ProfileGame game;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outcome = game.outcome;
    final (background, foreground) = switch (outcome) {
      'V' => (colors.primary, colors.onPrimary),
      'D' => (colors.error, colors.onError),
      _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
    };
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: Text(
        outcome ?? '–',
        semanticsLabel: switch (outcome) {
          'V' => 'Vitória',
          'E' => 'Empate',
          'D' => 'Derrota',
          _ => 'Sem placar',
        },
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}
