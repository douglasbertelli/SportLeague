import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../games/data/player_stats_repository.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/season_button.dart';
import '../../teams/presentation/team_stats_widgets.dart';
import '../domain/athlete.dart';

/// Perfil do atleta: foto, posição e número e os números em todos os jogos
/// (jogos, gols, assistências, cartões e vezes em que foi o craque).
class AthleteProfilePage extends ConsumerWidget {
  const AthleteProfilePage({super.key, required this.athlete});

  final Athlete athlete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final totals = ref.watch(teamPlayerTotalsProvider(athlete.teamId));
    final photoUrl = athlete.photoUrl;
    final details = [
      ?athlete.position,
      if (athlete.jerseyNumber case final number?) 'Nº $number',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(athlete.displayName),
        actions: [
          if (ref.watch(canManageTeamProvider))
            IconButton(
              tooltip: 'Editar atleta',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.editAthlete, extra: athlete),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 48,
              foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
              onForegroundImageError: photoUrl == null ? null : (_, _) {},
              child: Text(
                athlete.displayName[0].toUpperCase(),
                style: theme.textTheme.headlineMedium,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            athlete.displayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          if (details.isNotEmpty)
            Text(
              details.join(' · '),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('Números', style: theme.textTheme.titleMedium),
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
              onPressed: () =>
                  ref.invalidate(teamPlayerTotalsProvider(athlete.teamId)),
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Erro ao carregar os números. Tentar novamente',
              ),
            ),
            data: (totals) {
              final mine = totals
                  .where((row) => row.athleteId == athlete.id)
                  .firstOrNull;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          StatTile(
                            value: '${mine?.games ?? 0}',
                            label: 'Jogos',
                          ),
                          StatTile(
                            value: '${mine?.goals ?? 0}',
                            label: 'Gols',
                            color: colors.primary,
                          ),
                          StatTile(
                            value: '${mine?.assists ?? 0}',
                            label: 'Assist.',
                            tooltip: 'Assistências',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          StatTile(
                            value: '${mine?.yellowCards ?? 0}',
                            label: 'Amarelos',
                          ),
                          StatTile(
                            value: '${mine?.redCards ?? 0}',
                            label: 'Vermelhos',
                            color: colors.error,
                          ),
                          StatTile(
                            value: '${mine?.bestPlayer ?? 0}',
                            label: 'Craque',
                            tooltip: 'Vezes em que foi o craque do jogo',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
