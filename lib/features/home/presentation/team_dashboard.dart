import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confetti_burst.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../board/presentation/board_teaser.dart';
import '../../games/data/dispute_repository.dart';
import '../../games/data/game_repository.dart';
import '../../games/data/player_stats_repository.dart';
import '../../games/domain/player_stats.dart';
import '../../games/domain/game.dart';
import '../../games/domain/game_event.dart';
import '../../games/domain/match_clock.dart';
import '../../games/presentation/contest_score.dart';
import '../../games/presentation/game_card.dart';
import '../../games/presentation/game_sheet_page.dart';
import '../../games/presentation/lineup_page.dart';
import '../../games/presentation/live_events.dart';
import '../../games/presentation/new_friendly.dart';
import '../../games/presentation/presence.dart';
import '../../profile/presentation/my_numbers_section.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/season_button.dart';
import '../../teams/presentation/team_logo.dart';
import '../../teams/presentation/team_stats_widgets.dart';
import 'game_countdown.dart';
import 'match_clock_panel.dart';

/// Dashboard do time ativo no Início: o time (com seguidores), o próximo
/// jogo, o que está pendente, as estatísticas e os últimos jogos.
class TeamDashboard extends ConsumerWidget {
  const TeamDashboard({super.key, this.onOpenGames, this.now});

  /// Leva à aba Jogos, já na aba de dentro do aviso (Pendentes, Realizados).
  final ValueChanged<GameStage>? onOpenGames;

  /// Agora (testes).
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider).value;
    if (team == null) {
      // O técnico e o jogador entram num time; o administrador cria.
      final coach = ref.watch(isCoachProvider) || ref.watch(isPlayerProvider);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                coach
                    ? 'Entre num time com o código de convite ou peça pelo '
                          'perfil do time para ver o painel dele.'
                    : 'Crie seu primeiro time para ver o painel dele.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    context.push(coach ? Routes.playerInvites : Routes.newTeam),
                icon: Icon(coach ? Icons.vpn_key_outlined : Icons.add),
                label: Text(coach ? 'Entrar num time' : 'Criar time'),
              ),
            ],
          ),
        ),
      );
    }
    // O técnico acompanha: sem marcar jogos, mexer no placar ou no relógio.
    // O jogador também não monta a escalação.
    final canManage = ref.watch(canManageTeamProvider);
    final isStaff = ref.watch(isTeamStaffProvider);

    final now = this.now ?? DateTime.now();
    final games = ref.watch(teamGamesProvider(team.id!)).value ?? const [];
    final stats = ref.watch(teamStatsProvider(team.id!)).value;
    // O card mostra o jogo em andamento ou o próximo marcado. O que acabou de
    // terminar (Fim de jogo, para contestar ou corrigir o placar) só fica
    // enquanto não houver outro jogo marcado.
    final upcoming = [
      for (final game in games)
        if (game.stageAt(now) == GameStage.scheduled) game,
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final justFinished = [
      for (final game in games)
        if (game.isLiveAt(now) && game.isFinishedAt(now)) game,
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final next = upcoming.isNotEmpty ? upcoming : justFinished.reversed;
    final pending = [
      for (final game in games)
        if (game.status == GameStatus.pending) game,
    ];
    final toAnswer = pending.where((g) => !g.isHostedBy(team.id!)).length;
    final waiting = pending.length - toAnswer;
    // Placares que o adversário contestou, para quem marcou responder.
    final disputed = [
      for (final dispute
          in ref.watch(teamDisputesProvider(team.id!)).value ?? const [])
        if (dispute.teamId != team.id) dispute,
    ].length;

    // O jogador vê primeiro os números dele (de um time ou de todos); o
    // administrador e o técnico, os do time, depois dos jogos.
    final player = ref.watch(isPlayerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (player) ...[
          const _DashboardTitle('Meus números', trailing: SeasonButton()),
          _MyTeamNumbers(teamId: team.id!),
          const SizedBox(height: 16),
        ],
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
          canManage: canManage,
          isStaff: isStaff,
          isPlayer: player,
        ),
        // Mural: avisos novos e o último publicado.
        const SizedBox(height: 8),
        BoardTeaser(teamId: team.id!),
        if (canManage && disputed > 0) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Badge(
                label: Text('$disputed'),
                child: const Icon(Icons.report_outlined),
              ),
              title: Text(
                disputed == 1
                    ? '1 placar contestado'
                    : '$disputed placares contestados',
              ),
              subtitle: const Text('O adversário discorda do placar lançado'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenGames?.call(GameStage.played),
            ),
          ),
        ],
        if (canManage && pending.isNotEmpty) ...[
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
              onTap: () => onOpenGames?.call(GameStage.pending),
            ),
          ),
        ],
        // A temporada vale para as estatísticas e para os atletas.
        if (!player) ...[
          const SizedBox(height: 16),
          const _DashboardTitle('Estatísticas', trailing: SeasonButton()),
          const SizedBox(height: 8),
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
      ],
    );
  }
}

/// Os números do jogador logado: jogos, gols, assistências, cartões e craque,
/// pelas súmulas da temporada. Os chips escolhem o time ativo entre os times
/// em que ele é atleta (o painel inteiro troca, com a cor do time) ou o Geral
/// (os números de todos somados).
class _MyTeamNumbers extends ConsumerStatefulWidget {
  const _MyTeamNumbers({required this.teamId});

  /// Time ativo.
  final String teamId;

  @override
  ConsumerState<_MyTeamNumbers> createState() => _MyTeamNumbersState();
}

class _MyTeamNumbersState extends ConsumerState<_MyTeamNumbers> {
  /// Geral: a soma de todos os times.
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(myTeamsProvider).value ?? const <Team>[];
    final selectedId = widget.teamId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Com um time só, o Geral é o próprio time.
        if (teams.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.functions, size: 18),
                    label: const Text('Geral'),
                    tooltip: 'Todos os seus times somados',
                    selected: _all,
                    onSelected: (_) => setState(() => _all = true),
                  ),
                ),
                for (final team in teams)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: TeamLogo(team: team, radius: 12),
                      label: Text(team.name),
                      selected: !_all && team.id == selectedId,
                      onSelected: (_) {
                        setState(() => _all = false);
                        ref
                            .read(selectedTeamIdProvider.notifier)
                            .select(team.id!);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        ref
            .watch(myTotalsProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => TextButton.icon(
                onPressed: () => ref.invalidate(myTotalsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text(
                  'Erro ao carregar os números. Tentar novamente',
                ),
              ),
              data: (totals) {
                // Sem súmula no time ainda, tudo zerado.
                final rows = [
                  for (final team in totals)
                    if (_all || team.teamId == selectedId) team.totals,
                ];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: PlayerTotalsGrid(totals: _sum(rows)),
                  ),
                );
              },
            ),
      ],
    );
  }
}

/// Soma os números de vários times (Geral).
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
  const _NextGameCard({
    required this.team,
    required this.game,
    this.clock,
    this.canManage = true,
    this.isStaff = true,
    this.isPlayer = false,
  });

  /// Atleta do time: responde se vai ao jogo.
  final bool isPlayer;

  /// Dono do time: marca amistosos (o técnico só acompanha).
  final bool canManage;

  /// Dono ou técnico: monta a escalação e a súmula (o jogador só vê).
  final bool isStaff;

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
                  if (widget.canManage) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => openNewFriendly(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Marcar amistoso'),
                    ),
                  ],
                ],
              )
            : live
            ? _LiveGameBody(
                team: team,
                game: game,
                clock: clock,
                canManage: widget.canManage,
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
                      // Com o relógio da partida iniciado (e no fim de
                      // jogo), quem mostra o tempo é ele; o "Começou" sai.
                      if (game.clock == null)
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
                  // O jogador confirma a presença; o dono e o técnico veem
                  // as respostas.
                  if (!live && widget.isPlayer) ...[
                    const SizedBox(height: 16),
                    Text('Você vai?', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    PresenceButtons(gameId: game.id!, teamId: team.id!),
                  ],
                  if (!live && widget.isStaff) ...[
                    const SizedBox(height: 8),
                    PresenceSummary(gameId: game.id!, teamId: team.id!),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            openLineup(context, game: game, teamId: team.id!),
                        icon: const Icon(Icons.format_list_numbered),
                        label: const Text('Escalação'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Card do jogo em andamento: situação (ao vivo, intervalo, fim), o placar
/// com os dois escudos, o relógio, as ações e os últimos lances.
class _LiveGameBody extends StatelessWidget {
  const _LiveGameBody({
    required this.team,
    required this.game,
    required this.clock,
    required this.canManage,
  });

  final Team team;
  final Game game;
  final DateTime Function()? clock;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final phase = game.clock?.phase;
    final finished = phase == MatchPhase.finished;
    final place = switch (game.venue) {
      final venue? => venue.name,
      null => game.location,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Situação e, ao lado, quando e onde começou.
        Row(
          children: [
            _LiveBadge(
              label: switch (phase) {
                MatchPhase.finished => 'Fim de jogo',
                MatchPhase.interval => 'Intervalo',
                _ => 'Jogo em andamento',
              },
              live: !finished && phase != MatchPhase.interval,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Começou às ${formatGameTime(game.scheduledAt)}',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _LiveScore(team: team, game: game),
        // O local, centralizado embaixo do placar.
        if (place != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        // Relógio e ações agrupados num cartão interno.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MatchClockPanel(game: game, viewerTeamId: team.id!, clock: clock),
              if (canManage &&
                  finished &&
                  !game.isHostedBy(team.id!) &&
                  game.hasScore) ...[
                const SizedBox(height: 12),
                _ContestButton(team: team, game: game),
              ],
              const SizedBox(height: 8),
              _LiveActions(team: team, game: game),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Últimos lances (todos veem, inclusive o jogador).
        Text('Lances', style: theme.textTheme.titleSmall),
        LiveTimeline(
          game: game,
          viewerTeamId: team.id!,
          limit: 4,
          onSeeAll: () =>
              openGameSheet(context, game: game, viewerTeamId: team.id!),
        ),
      ],
    );
  }
}

/// "Jogo em andamento" com a bolinha vermelha; intervalo e fim, sem ela.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label, required this.live});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: live ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.error,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: live ? colors.onErrorContainer : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lance, ao vivo, súmula e escalação, numa barra de ícones.
class _LiveActions extends ConsumerWidget {
  const _LiveActions({required this.team, required this.game});

  final Team team;
  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(isTeamStaffProvider);
    if (!staff) return const SizedBox.shrink();
    Widget action(IconData icon, String label, VoidCallback onTap) => Flexible(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
    // Do primeiro ao último encostados nas bordas, espaço igual entre eles
    // (em tela estreita, os textos encolhem).
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Cartão, substituição e pênalti (e gol, para quem marcou): o dono
        // de cada time.
        if (ref.watch(canManageTeamProvider))
          action(
            Icons.add_circle_outline,
            'Lance',
            () =>
                addLiveEvent(context, ref, game: game, viewerTeamId: team.id!),
          ),
        action(
          Icons.share_outlined,
          'Ao vivo',
          () => shareLiveGame(context, ref, game: game, viewerTeamId: team.id!),
        ),
        action(
          Icons.assignment_outlined,
          'Súmula',
          () => openGameSheet(context, game: game, viewerTeamId: team.id!),
        ),
        action(
          Icons.format_list_numbered,
          'Escalação',
          () => openLineup(context, game: game, teamId: team.id!),
        ),
      ],
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

  /// Salva o placar; diz se deu certo.
  Future<bool> _save(int mine, int theirs) async {
    setState(() => _saving = true);
    final teamId = widget.team.id!;
    try {
      await ref
          .read(gameRepositoryProvider)
          .setScore(widget.game.id!, teamScore: mine, opponentScore: theirs);
      ref
        ..invalidate(teamGamesProvider(teamId))
        ..invalidate(teamStatsProvider(teamId));
      return true;
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Gol de um lado: vira um lance da súmula ao vivo (o banco soma no
  /// placar). Tirar gol apaga o último lance de gol daquele lado; sem lance
  /// (placar lançado antes), corrige o placar à mão.
  Future<void> _goal(GameSide side, int goals, int mine, int theirs) async {
    final current = side == GameSide.host ? mine : theirs;
    if (goals > current) {
      setState(() => _saving = true);
      try {
        await addLiveEvent(
          context,
          ref,
          game: widget.game,
          viewerTeamId: widget.team.id!,
          side: side,
          kind: GameEventKind.goal,
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    final removed = await removeLastGoal(
      context,
      ref,
      game: widget.game,
      viewerTeamId: widget.team.id!,
      scoringSide: side,
    );
    if (removed || !mounted) return;
    if (side == GameSide.host) {
      await _save(goals, theirs);
    } else {
      await _save(mine, goals);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = widget.team;
    final game = widget.game;
    // Só o dono de quem marcou o jogo mexe no placar (o técnico acompanha).
    final canEdit =
        game.isHostedBy(team.id!) && ref.watch(canManageTeamProvider);
    final (mine, theirs) = game.scoreFor(team.id!) ?? (0, 0);
    final enabled = canEdit && !_saving;

    final opponent = game.opponentNameFor(team.id!);
    final scoreStyle = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Escudo e sigla do time ("UNI", "JUV"), nas pontas do placar, como na
    // TV: os dois lados ocupam o mesmo espaço. O nome inteiro fica para o
    // leitor de tela (e aparece ao segurar o dedo).
    Widget mark(String name, String? logoUrl) => SizedBox(
      // Do tamanho do escudo: ele encosta nas bordas do card.
      width: 52,
      child: Tooltip(
        message: name,
        child: Column(
          children: [
            TeamLogo.url(logoUrl: logoUrl, radius: 26),
            const SizedBox(height: 6),
            Text(
              teamAbbreviation(name),
              semanticsLabel: name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
    // Gols de um lado e, embaixo, os botões − e + (só para quem marcou o
    // jogo).
    Widget goals(String name, int value, void Function(int) change) => Column(
      children: [
        Text(
          '$value',
          semanticsLabel: '$value gols do $name',
          style: scoreStyle,
        ),
        if (canEdit)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Tirar gol do $name',
                visualDensity: VisualDensity.compact,
                onPressed: enabled && value > 0
                    ? () => change(value - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton.filledTonal(
                tooltip: 'Gol do $name',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? () => change(value + 1) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
      ],
    );

    return Row(
      children: [
        mark(team.name, team.logoUrl),
        // O placar no meio, com os botões embaixo de cada número; em tela
        // estreita, encolhe em vez de estourar.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                goals(
                  team.name,
                  mine,
                  (value) => _goal(GameSide.host, value, mine, theirs),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
                  child: Text(
                    '×',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                goals(
                  opponent,
                  theirs,
                  (value) => _goal(GameSide.opponent, value, mine, theirs),
                ),
              ],
            ),
          ),
        ),
        mark(opponent, game.opponentLogoFor(team.id!)),
      ],
    );
  }
}

class _DashboardTitle extends StatelessWidget {
  const _DashboardTitle(this.text, {this.trailing});

  final String text;

  /// À direita do título (ex.: a temporada).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// No fim de jogo, o adversário contesta o placar direto do card; depois de
/// enviar, fica o aviso de que espera a resposta.
class _ContestButton extends ConsumerWidget {
  const _ContestButton({required this.team, required this.game});

  final Team team;
  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sent = (ref.watch(teamDisputesProvider(team.id!)).value ?? const [])
        .any((dispute) => dispute.gameId == game.id);
    if (sent) {
      return Center(
        child: DisputeSentBadge(hostName: game.opponentNameFor(team.id!)),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => contestScore(
        context,
        ref,
        game: game,
        viewerTeamId: team.id!,
        myTeamName: team.name,
      ),
      icon: const Icon(Icons.report_outlined),
      label: const Text('Contestar placar'),
    );
  }
}
