import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/game.dart';
import '../../games/presentation/game_card.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../../teams/presentation/team_stats_widgets.dart';
import 'game_countdown.dart';

/// Dashboard do time ativo no Início: o time (com seguidores), o próximo
/// jogo, o que está pendente, as estatísticas e os últimos jogos.
class TeamDashboard extends ConsumerWidget {
  const TeamDashboard({super.key, this.onOpenGames, this.now});

  /// Leva à aba Jogos (pendências).
  final VoidCallback? onOpenGames;

  /// Agora (testes).
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider).value;
    if (team == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Crie seu primeiro time para ver o painel dele.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push(Routes.newTeam),
                icon: const Icon(Icons.add),
                label: const Text('Criar time'),
              ),
            ],
          ),
        ),
      );
    }

    final now = this.now ?? DateTime.now();
    final games = ref.watch(teamGamesProvider(team.id!)).value ?? const [];
    final stats = ref.watch(teamStatsProvider(team.id!)).value;
    final next = [
      for (final game in games)
        if (game.stageAt(now) == GameStage.scheduled) game,
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final pending = [
      for (final game in games)
        if (game.status == GameStatus.pending) game,
    ];
    final toAnswer = pending.where((g) => !g.isHostedBy(team.id!)).length;
    final waiting = pending.length - toAnswer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TeamHeader(
          team: team,
          followers: stats?.followers,
          following: stats?.following,
        ),
        const SizedBox(height: 8),
        _NextGameCard(
          team: team,
          game: next.firstOrNull,
          clock: this.now == null ? null : () => now,
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Badge(
                label: Text('$toAnswer'),
                isLabelVisible: toAnswer > 0,
                child: const Icon(Icons.mark_email_unread_outlined),
              ),
              title: Text(
                toAnswer > 0
                    ? '$toAnswer ${toAnswer == 1 ? 'convite' : 'convites'} '
                          'para responder'
                    : 'Nenhum convite para responder',
              ),
              subtitle: waiting > 0
                  ? Text(
                      '$waiting ${waiting == 1 ? 'amistoso aguardando' : 'amistosos aguardando'} '
                      'o adversário',
                    )
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenGames,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const _DashboardTitle('Estatísticas'),
        if (stats == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          StatsGrid(stats: stats),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Últ. jogos',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 16),
                  if (stats.recent.isEmpty)
                    const Expanded(child: Text('Nenhum amistoso realizado'))
                  else
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        // Do mais antigo para o mais recente, como uma linha
                        // do tempo.
                        children: [
                          for (final game in stats.recent.reversed)
                            Tooltip(
                              message:
                                  '${game.opponent} · '
                                  '${formatGameDay(game.scheduledAt)}',
                              child: OutcomeBadge(game: game, radius: 14),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Logo, nome, resumo, seguidores e o atalho para o perfil público.
class _TeamHeader extends StatelessWidget {
  const _TeamHeader({
    required this.team,
    required this.followers,
    required this.following,
  });

  final Team team;
  final int? followers;
  final int? following;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.teamProfile, extra: team.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              TeamLogo(team: team, radius: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: theme.textTheme.titleLarge),
                    Text(team.summary, style: muted),
                    const SizedBox(height: 4),
                    Text(
                      '${followers ?? '–'} seguidores · '
                      '${following ?? '–'} seguindo',
                      style: muted,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, semanticLabel: 'Ver perfil'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Próximo amistoso marcado ou o atalho para marcar um.
class _NextGameCard extends StatelessWidget {
  const _NextGameCard({required this.team, required this.game, this.clock});

  final Team team;
  final Game? game;

  /// Hora atual do contador (testes).
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = this.game;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: game == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Próximo jogo', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const Text('Nenhum amistoso marcado.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push(Routes.newGame),
                    icon: const Icon(Icons.add),
                    label: const Text('Marcar amistoso'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Próximo jogo',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      GameCountdown(startsAt: game.scheduledAt, clock: clock),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TeamLogo.url(
                        logoUrl: game.opponentLogoFor(team.id!),
                        radius: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OpponentWithSide(
                              opponent: game.opponentNameFor(team.id!),
                              isHome: game.isHomeFor(team.id!),
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              '${formatGameDay(game.scheduledAt)} às '
                              '${formatGameTime(game.scheduledAt)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (switch (game.venue) {
                        final venue? => '${venue.name} · ${venue.cityLine}',
                        null => game.location,
                      }
                      case final place?) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(place)),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _DashboardTitle extends StatelessWidget {
  const _DashboardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
