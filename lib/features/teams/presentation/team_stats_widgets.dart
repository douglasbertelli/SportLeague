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

/// Selo "Casa" (o time é mandante) ou "Fora" (visitante), ao lado do
/// adversário.
class HomeAwayBadge extends StatelessWidget {
  const HomeAwayBadge({super.key, required this.isHome});

  final bool isHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (background, foreground) = isHome
        ? (colors.primaryContainer, colors.onPrimaryContainer)
        : (colors.surfaceContainerHighest, colors.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isHome ? 'Casa' : 'Fora',
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "x Adversário" com o selo Casa/Fora logo depois.
class OpponentWithSide extends StatelessWidget {
  const OpponentWithSide({
    super.key,
    required this.opponent,
    required this.isHome,
    this.style,
  });

  final String opponent;
  final bool isHome;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            'x $opponent',
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        HomeAwayBadge(isHome: isHome),
      ],
    );
  }
}
