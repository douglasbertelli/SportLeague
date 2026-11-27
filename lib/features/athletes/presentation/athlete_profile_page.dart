import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../reports/domain/content_report.dart';
import '../../reports/presentation/report_sheet.dart';
import '../../games/data/player_stats_repository.dart';
import '../../games/domain/player_stats.dart';
import '../../profile/presentation/my_numbers_section.dart';
import '../../sports/domain/sport_rules.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/season_button.dart';
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
            )
          // Quem não administra o time e não é o próprio atleta pode
          // denunciar (ex.: foto ou nome ofensivo).
          else if (athlete.id case final id?
              when athlete.profileId != ref.watch(currentUserIdProvider))
            ReportMenuButton(target: ReportTarget.athlete, targetId: id),
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
                  child: PlayerTotalsGrid(
                    totals:
                        mine ??
                        AthleteTotals(
                          athleteId: athlete.id ?? '',
                          name: athlete.name,
                        ),
                    // As estatísticas do esporte do time do atleta.
                    rules:
                        ref
                            .watch(teamByIdProvider(athlete.teamId))
                            .value
                            ?.rules ??
                        footballRules,
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
