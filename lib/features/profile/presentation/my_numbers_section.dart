import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../games/data/player_stats_repository.dart';
import '../../games/domain/player_stats.dart';
import '../../teams/presentation/season_button.dart';
import '../../teams/presentation/team_logo.dart';
import '../../teams/presentation/team_stats_widgets.dart';

/// Meus números (Perfil do jogador): a soma de todos os times em que ele é
/// atleta e, abaixo, o que fez em cada um.
class MyNumbersSection extends ConsumerWidget {
  const MyNumbersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = ref.watch(myTotalsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text('Meus números', style: theme.textTheme.titleMedium),
            ),
            const SeasonButton(),
          ],
        ),
        const SizedBox(height: 8),
        totals.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => TextButton.icon(
            onPressed: () => ref.invalidate(myTotalsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os números. Tentar novamente'),
          ),
          data: (teams) {
            if (teams.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Entre num time para ver aqui seus jogos, gols e '
                    'assistências.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _TotalsGrid(
                      totals: _sum([for (final team in teams) team.totals]),
                    ),
                  ),
                ),
                // Com um time só, a soma já é o time.
                if (teams.length > 1) ...[
                  const SizedBox(height: 16),
                  Text('Por time', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final team in teams) _TeamTotalsCard(team: team),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

AthleteTotals _sum(List<AthleteTotals> rows) => AthleteTotals(
  athleteId: '',
  name: '',
  games: rows.fold(0, (sum, row) => sum + row.games),
  goals: rows.fold(0, (sum, row) => sum + row.goals),
  assists: rows.fold(0, (sum, row) => sum + row.assists),
  yellowCards: rows.fold(0, (sum, row) => sum + row.yellowCards),
  redCards: rows.fold(0, (sum, row) => sum + row.redCards),
  bestPlayer: rows.fold(0, (sum, row) => sum + row.bestPlayer),
);

/// Jogos, gols, assistências, cartões e craque, em duas linhas.
class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.totals});

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

/// Um time do jogador: logo, nome, número e posição, e os números nele.
class _TeamTotalsCard extends StatelessWidget {
  const _TeamTotalsCard({required this.team});

  final MyTeamTotals team;

  @override
  Widget build(BuildContext context) {
    final totals = team.totals;
    final details = [
      ?totals.position,
      if (totals.jerseyNumber case final number?) 'Nº $number',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          children: [
            ListTile(
              leading: TeamLogo.url(logoUrl: team.teamLogoUrl),
              title: Text(team.teamName),
              subtitle: details.isEmpty ? null : Text(details.join(' · ')),
            ),
            _TotalsGrid(totals: totals),
          ],
        ),
      ),
    );
  }
}
