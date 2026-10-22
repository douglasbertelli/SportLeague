import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/no_team_placeholder.dart';
import '../data/game_repository.dart';
import '../domain/game.dart';

/// Aba Jogos do administrador: amistosos do time ativo divididos em Marcados,
/// Pendentes, Cancelados e Realizados.
class GamesTab extends ConsumerWidget {
  const GamesTab({super.key, this.now});

  /// Referência para separar marcados e realizados (testes).
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
        label: const Text('Novo amistoso'),
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
          final byStage = {
            for (final stage in GameStage.values)
              stage: [
                for (final game in games)
                  if (game.stageAt(now) == stage) game,
              ],
          };
          // Próximos primeiro; já realizados e cancelados, mais recentes
          // primeiro.
          for (final MapEntry(key: stage, value: list) in byStage.entries) {
            list.sort(
              (a, b) => switch (stage) {
                GameStage.scheduled ||
                GameStage.pending => a.scheduledAt.compareTo(b.scheduledAt),
                _ => b.scheduledAt.compareTo(a.scheduledAt),
              },
            );
          }

          return DefaultTabController(
            length: GameStage.values.length,
            child: Column(
              children: [
                // Rola na horizontal quando as abas não cabem na tela.
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final stage in GameStage.values)
                      Tab(text: '${stage.label} (${byStage[stage]!.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final stage in GameStage.values)
                        _StageList(
                          stage: stage,
                          games: byStage[stage]!,
                          teamId: teamId,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StageList extends ConsumerWidget {
  const _StageList({
    required this.stage,
    required this.games,
    required this.teamId,
  });

  final GameStage stage;
  final List<Game> games;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (games.isEmpty) {
      return EmptyState(
        icon: switch (stage) {
          GameStage.scheduled => Icons.event_available,
          GameStage.pending => Icons.hourglass_empty,
          GameStage.canceled => Icons.event_busy,
          GameStage.played => Icons.sports_soccer,
        },
        title: switch (stage) {
          GameStage.scheduled => 'Nenhum amistoso marcado',
          GameStage.pending => 'Nenhum amistoso pendente',
          GameStage.canceled => 'Nenhum amistoso cancelado',
          GameStage.played => 'Nenhum amistoso realizado',
        },
        message: switch (stage) {
          GameStage.scheduled =>
            'Marque amistosos contra times da mesma modalidade pelo botão '
                'abaixo.',
          GameStage.pending =>
            'Amistosos contra times da plataforma ficam aqui até o '
                'adversário aceitar.',
          GameStage.canceled =>
            'Amistosos cancelados ou recusados por um dos times aparecem aqui.',
          GameStage.played =>
            'Amistosos marcados aparecem aqui depois da data do jogo.',
        },
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.refresh(teamGamesProvider(teamId).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          for (final game in games)
            _GameCard(game: game, viewerTeamId: teamId, stage: stage),
        ],
      ),
    );
  }
}

/// Jogo do ponto de vista do time ativo ([viewerTeamId]). Quem marcou edita ao
/// tocar; o adversário aceita ou recusa o pendente e pode cancelar o marcado.
class _GameCard extends ConsumerStatefulWidget {
  const _GameCard({
    required this.game,
    required this.viewerTeamId,
    required this.stage,
  });

  final Game game;
  final String viewerTeamId;
  final GameStage stage;

  @override
  ConsumerState<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<_GameCard> {
  bool _loading = false;

  Game get _game => widget.game;

  Future<void> _respond({required bool accept}) async {
    final opponentName = _game.opponentNameFor(widget.viewerTeamId);
    if (!accept) {
      final pending = _game.status == GameStatus.pending;
      final confirmed = await confirmAction(
        context,
        title: pending ? 'Recusar amistoso?' : 'Cancelar amistoso?',
        message: pending
            ? 'O amistoso contra $opponentName será recusado e irá para '
                  'Cancelados.'
            : 'O amistoso contra $opponentName será cancelado para os dois '
                  'times.',
        confirmLabel: pending ? 'Recusar' : 'Cancelar amistoso',
        cancelLabel: 'Voltar',
      );
      if (!confirmed) return;
    }

    setState(() => _loading = true);
    try {
      final repository = ref.read(gameRepositoryProvider);
      await (accept
          ? repository.accept(_game.id!)
          : repository.cancel(_game.id!));
      ref.invalidate(teamGamesProvider(widget.viewerTeamId));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewer = widget.viewerTeamId;
    final isHost = _game.isHostedBy(viewer);
    final opponentName = _game.opponentNameFor(viewer);
    final result = _game.resultLabelFor(viewer);
    final pending = _game.status == GameStatus.pending;
    final upcomingScheduled = widget.stage == GameStage.scheduled;

    final lines = [
      formatGameDate(context, _game.scheduledAt),
      ?_game.location,
      if (!isHost) 'Marcado por $opponentName',
      if (pending && isHost) 'Aguardando $opponentName aceitar',
      if (pending && !isHost) 'Aguardando sua resposta',
      if (_game.status == GameStatus.canceled)
        switch (_game.canceledByTeamId) {
          null => 'Cancelado: o adversário foi excluído',
          final id when id == viewer => 'Cancelado pelo seu time',
          _ => 'Cancelado por $opponentName',
        },
    ];

    final actions = <Widget>[
      if (pending && !isHost) ...[
        TextButton(
          onPressed: _loading ? null : () => _respond(accept: false),
          child: const Text('Recusar'),
        ),
        FilledButton(
          onPressed: _loading ? null : () => _respond(accept: true),
          child: const Text('Aceitar'),
        ),
      ],
      if (upcomingScheduled && !isHost)
        TextButton(
          onPressed: _loading ? null : () => _respond(accept: false),
          child: const Text('Cancelar amistoso'),
        ),
    ];

    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text('x $opponentName'),
            subtitle: Text(lines.join('\n')),
            isThreeLine: lines.length > 1,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_game.modality case final modality?)
                  Text(modality.label, style: theme.textTheme.labelSmall),
                if (result != null)
                  Text(
                    result,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
            // Só quem marcou edita, e cancelado não muda mais.
            onTap: isHost && _game.status != GameStatus.canceled
                ? () => context.push(Routes.editGame, extra: _game)
                : null,
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: actions,
              ),
            ),
        ],
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
