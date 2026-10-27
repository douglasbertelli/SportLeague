import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/empty_state.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/no_team_placeholder.dart';
import '../data/game_repository.dart';
import '../data/games_tab_request.dart';
import '../domain/game.dart';
import 'game_card.dart';

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
        child: TextButton.icon(
          onPressed: () => ref.invalidate(myTeamsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Erro ao carregar os times. Tentar novamente'),
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
      // Só o dono marca amistosos (o técnico acompanha).
      floatingActionButton: ref.watch(canManageTeamProvider)
          ? FloatingActionButton.extended(
              heroTag: 'new-game',
              onPressed: () => context.push(Routes.newGame),
              icon: const Icon(Icons.add),
              label: const Text('Novo amistoso'),
            )
          : null,
      body: games.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(teamGamesProvider(teamId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os jogos. Tentar novamente'),
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
            // Aberta por um aviso do Início: já na aba dele.
            initialIndex: ref.read(gamesTabRequestProvider)?.stage.index ?? 0,
            child: Column(
              children: [
                _FollowRequests(),
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

/// Troca de aba quando um aviso do Início pede (com a aba Jogos já aberta).
class _FollowRequests extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(gamesTabRequestProvider, (_, request) {
      if (request != null) {
        DefaultTabController.of(context).animateTo(request.stage.index);
      }
    });
    return const SizedBox.shrink();
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
            GameCard(game: game, viewerTeamId: teamId, stage: stage),
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
