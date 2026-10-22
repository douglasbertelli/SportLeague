import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/empty_state.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/no_team_placeholder.dart';
import '../data/game_repository.dart';
import '../domain/game.dart';

/// Aba Jogos do administrador: jogos do time ativo, próximos e anteriores.
class GamesTab extends ConsumerWidget {
  const GamesTab({super.key, this.now});

  /// Referência para separar próximos e anteriores (testes).
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    return switch (team) {
      AsyncValue(value: final team?) => _GameList(
        teamId: team.id!,
        now: now ?? DateTime.now(),
      ),
      AsyncValue(hasValue: true) => const NoTeamPlaceholder(),
      AsyncValue(hasError: true) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(myTeamsProvider),
          child: const Text('Erro ao carregar os times. Tentar novamente'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _GameList extends ConsumerWidget {
  const _GameList({required this.teamId, required this.now});

  final String teamId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(teamGamesProvider(teamId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-game',
        onPressed: () => context.push(Routes.newGame),
        icon: const Icon(Icons.add),
        label: const Text('Novo jogo'),
      ),
      body: games.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(teamGamesProvider(teamId)),
            child: const Text('Erro ao carregar os jogos. Tentar novamente'),
          ),
        ),
        data: (games) {
          if (games.isEmpty) {
            return const EmptyState(
              icon: Icons.sports_soccer,
              title: 'Nenhum jogo neste time',
              message:
                  'Marque amistosos e jogos de campeonato pelo botão abaixo.',
            );
          }
          final upcoming = games.where((g) => !g.scheduledAt.isBefore(now));
          final past = games.where((g) => g.scheduledAt.isBefore(now)).toList()
            ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

          return RefreshIndicator(
            onRefresh: () => ref.refresh(teamGamesProvider(teamId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (upcoming.isNotEmpty) ...[
                  const _SectionTitle('Próximos'),
                  for (final game in upcoming) _GameCard(game: game),
                ],
                if (past.isNotEmpty) ...[
                  if (upcoming.isNotEmpty) const SizedBox(height: 16),
                  const _SectionTitle('Anteriores'),
                  for (final game in past) _GameCard(game: game),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = game.resultLabel;
    return Card(
      child: ListTile(
        title: Text('x ${game.opponent}'),
        subtitle: Text(
          [
            formatGameDate(context, game.scheduledAt),
            ?game.location,
          ].join('\n'),
        ),
        isThreeLine: game.location != null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(game.type.label, style: theme.textTheme.labelSmall),
            if (result != null)
              Text(
                result,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        onTap: () => context.push(Routes.editGame, extra: game),
      ),
    );
  }
}

/// "sáb., 25 de out. de 2026 · 15:00", no idioma do app.
String formatGameDate(BuildContext context, DateTime date) {
  final localizations = MaterialLocalizations.of(context);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat: true,
  );
  return '${localizations.formatMediumDate(date)} · $time';
}
