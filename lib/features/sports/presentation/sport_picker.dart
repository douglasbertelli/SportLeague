import 'package:flutter/material.dart';

import '../../teams/domain/team.dart';
import '../domain/sport_rules.dart';

/// Ícone de cada esporte.
IconData sportIcon(Sport sport) => switch (sport) {
  Sport.football => Icons.sports_soccer,
  Sport.volleyball => Icons.sports_volleyball,
  Sport.basketball => Icons.sports_basketball,
};

/// Escolha do esporte em cards lado a lado (ícone e nome). Embaixo dela, a
/// tela mostra só as modalidades do esporte escolhido.
class SportPicker extends StatelessWidget {
  const SportPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.sports = supportedSports,
  });

  final Sport selected;
  final ValueChanged<Sport> onChanged;
  final List<Sport> sports;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (index, sport) in sports.indexed) ...[
          if (index > 0) const SizedBox(width: 12),
          Expanded(
            child: _SportCard(
              sport: sport,
              selected: sport == selected,
              onTap: () => onChanged(sport),
            ),
          ),
        ],
      ],
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  final Sport sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Icon(sportIcon(sport), size: 36, color: foreground),
                const SizedBox(height: 8),
                Text(
                  sport.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? colors.onSurface : foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
