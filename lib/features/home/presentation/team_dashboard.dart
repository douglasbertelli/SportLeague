import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confetti_burst.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/data/dispute_repository.dart';
import '../../games/data/game_repository.dart';
import '../../games/data/player_stats_repository.dart';
import '../../games/domain/player_stats.dart';
import '../../games/domain/game.dart';
import '../../games/domain/match_clock.dart';
import '../../games/presentation/contest_score.dart';
import '../../games/presentation/game_card.dart';
import '../../games/presentation/game_sheet_page.dart';
import '../../games/presentation/lineup_page.dart';
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
                      onPressed: () => context.push(Routes.newGame),
                      icon: const Icon(Icons.add),
                      label: const Text('Marcar amistoso'),
                    ),
                  ],
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
                  if (live) ...[
                    const Divider(height: 32),
                    MatchClockPanel(
                      game: game,
                      viewerTeamId: team.id!,
                      clock: clock,
                    ),
                    const SizedBox(height: 16),
                    _LiveScore(team: team, game: game),
                    if (widget.canManage &&
                        game.clock?.phase == MatchPhase.finished &&
                        !game.isHostedBy(team.id!) &&
                        game.hasScore) ...[
                      const SizedBox(height: 16),
                      _ContestButton(team: team, game: game),
                    ],
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

  /// Gol do próprio time: depois do placar, pergunta quem fez.
  Future<void> _ownGoals(int goals, int mine, int theirs) async {
    if (!await _save(goals, theirs) || goals <= mine || !mounted) return;
    await askGoalScorer(
      context,
      ref,
      game: widget.game,
      teamId: widget.team.id!,
    );
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

    return Column(
      children: [
        Row(
          children: [
            side(team.name, mine, (goals) => _ownGoals(goals, mine, theirs)),
            Text('×', style: theme.textTheme.headlineSmall),
            side(
              game.opponentNameFor(team.id!),
              theirs,
              (goals) => _save(mine, goals),
            ),
          ],
        ),
        // Os dois times lançam a súmula e a escalação dos seus atletas (o
        // dono e o técnico; o jogador acompanha).
        if (ref.watch(isTeamStaffProvider))
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () =>
                    openGameSheet(context, game: game, viewerTeamId: team.id!),
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Súmula do jogo'),
              ),
              TextButton.icon(
                onPressed: () =>
                    openLineup(context, game: game, teamId: team.id!),
                icon: const Icon(Icons.format_list_numbered),
                label: const Text('Escalação'),
              ),
            ],
          ),
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
