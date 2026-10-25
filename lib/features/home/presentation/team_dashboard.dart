import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confetti_burst.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/game.dart';
import '../../games/domain/match_clock.dart';
import '../../games/presentation/game_card.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../../teams/presentation/team_stats_widgets.dart';
import 'game_countdown.dart';
import 'match_clock_panel.dart';

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
    // O jogo em andamento continua no card até ganhar placar (ou passar o
    // tempo de jogo); depois, o próximo marcado.
    final next = [
      for (final game in games)
        if (game.stageAt(now) == GameStage.scheduled || game.isLiveAt(now))
          game,
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
                      '${followers ?? '–'} '
                      '${followers == 1 ? 'seguidor' : 'seguidores'} · '
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

/// Próximo amistoso marcado (ou o em andamento) ou o atalho para marcar um.
/// Quando a contagem chega a zero, o título vira "Jogo em andamento" e
/// estouram confetes.
class _NextGameCard extends StatefulWidget {
  const _NextGameCard({required this.team, required this.game, this.clock});

  final Team team;
  final Game? game;

  /// Hora atual do contador (testes).
  final DateTime Function()? clock;

  @override
  State<_NextGameCard> createState() => _NextGameCardState();
}

class _NextGameCardState extends State<_NextGameCard> {
  bool _startedNow = false;

  @override
  void didUpdateWidget(_NextGameCard old) {
    super.didUpdateWidget(old);
    if (old.game?.id != widget.game?.id) _startedNow = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = widget.team;
    final game = widget.game;
    final clock = widget.clock;
    final live =
        game != null &&
        (_startedNow || !game.scheduledAt.isAfter((clock ?? DateTime.now)()));
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
                        child: Text(switch ((live, game.clock?.phase)) {
                          (true, MatchPhase.finished) => 'Fim de jogo',
                          (true, _) => 'Jogo em andamento',
                          (false, _) => 'Próximo jogo',
                        }, style: theme.textTheme.titleSmall),
                      ),
                      GameCountdown(
                        startsAt: game.scheduledAt,
                        clock: clock,
                        onStarted: () {
                          setState(() => _startedNow = true);
                          showConfettiBurst(context);
                        },
                      ),
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
                  if (live) ...[
                    const Divider(height: 32),
                    MatchClockPanel(
                      game: game,
                      viewerTeamId: team.id!,
                      clock: clock,
                    ),
                    const SizedBox(height: 16),
                    _LiveScore(team: team, game: game),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Placar do jogo em andamento. Quem marcou o jogo (o único que lança o
/// placar) atualiza gol a gol; o adversário só acompanha.
class _LiveScore extends ConsumerStatefulWidget {
  const _LiveScore({required this.team, required this.game});

  final Team team;
  final Game game;

  @override
  ConsumerState<_LiveScore> createState() => _LiveScoreState();
}

class _LiveScoreState extends ConsumerState<_LiveScore> {
  bool _saving = false;

  Future<void> _save(int mine, int theirs) async {
    setState(() => _saving = true);
    final teamId = widget.team.id!;
    try {
      await ref
          .read(gameRepositoryProvider)
          .setScore(widget.game.id!, teamScore: mine, opponentScore: theirs);
      ref
        ..invalidate(teamGamesProvider(teamId))
        ..invalidate(teamStatsProvider(teamId));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = widget.team;
    final game = widget.game;
    final canEdit = game.isHostedBy(team.id!);
    final (mine, theirs) = game.scoreFor(team.id!) ?? (0, 0);
    final enabled = canEdit && !_saving;

    Widget side(String name, int goals, void Function(int) change) => Expanded(
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (canEdit)
                IconButton(
                  tooltip: 'Tirar gol do $name',
                  onPressed: enabled && goals > 0
                      ? () => change(goals - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              Text(
                '$goals',
                semanticsLabel: '$goals gols do $name',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'Gol do $name',
                  onPressed: enabled ? () => change(goals + 1) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
            ],
          ),
        ],
      ),
    );

    return Row(
      children: [
        side(team.name, mine, (goals) => _save(goals, theirs)),
        Text('×', style: theme.textTheme.headlineSmall),
        side(
          game.opponentNameFor(team.id!),
          theirs,
          (goals) => _save(mine, goals),
        ),
      ],
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
