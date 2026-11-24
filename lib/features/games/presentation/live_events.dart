import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../../invites/data/invite_repository.dart' show shareTextProvider;
import '../../teams/data/team_repository.dart';
import '../data/game_event_repository.dart';
import '../data/game_repository.dart';
import '../data/player_stats_repository.dart';
import '../domain/game.dart';
import '../domain/game_event.dart';

/// Lado do jogo de quem vê: quem marcou ou o adversário.
GameSide viewerSide(Game game, String viewerTeamId) =>
    game.isHostedBy(viewerTeamId) ? GameSide.host : GameSide.opponent;

/// Se o dono do time [viewerTeamId] pode lançar (ou apagar) este lance, como
/// no banco (private.can_add_game_event): quem marcou lança os gols dos dois
/// lados e tudo do convidado; o adversário da plataforma, os lances dele
/// menos gols.
bool canAddGameEvent(
  Game game,
  String viewerTeamId, {
  required GameSide side,
  required GameEventKind kind,
}) {
  if (game.isHostedBy(viewerTeamId)) {
    return side == GameSide.host ||
        kind.isScoring ||
        game.opponentTeamId == null;
  }
  return side == GameSide.opponent &&
      game.opponentTeamId == viewerTeamId &&
      !kind.isScoring;
}

/// Se o dono do time [viewerTeamId] completa autor e assistência deste
/// lance (o lado dele; contra convidado, quem marcou).
bool canCompleteGameEvent(Game game, String viewerTeamId, GameEvent event) =>
    event.side == viewerSide(game, viewerTeamId) ||
    (game.isHostedBy(viewerTeamId) && game.opponentTeamId == null);

/// Atualiza o que muda com um lance: lances, placar e súmula.
void _refreshAfterEvent(WidgetRef ref, Game game, String viewerTeamId) {
  ref
    ..invalidate(gameEventsProvider(game.id!))
    ..invalidate(teamGamesProvider(viewerTeamId))
    ..invalidate(gameStatsProvider(game.id!))
    ..invalidate(teamPlayerTotalsProvider(viewerTeamId));
}

/// Abre o lançamento de um lance. Com [kind], já vem escolhido (o "+" do
/// placar abre no gol do lado [side]).
Future<void> addLiveEvent(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String viewerTeamId,
  GameSide? side,
  GameEventKind? kind,
}) async {
  final mySide = viewerSide(game, viewerTeamId);
  final athletes = await ref.read(activeAthletesProvider(viewerTeamId).future);
  if (!context.mounted) return;
  final draft = await showAppSheet<_EventDraft>(
    context,
    builder: (_) => _LiveEventSheet(
      game: game,
      viewerTeamId: viewerTeamId,
      mySide: mySide,
      athletes: athletes,
      initialSide: side ?? mySide,
      initialKind: kind,
    ),
  );
  if (draft == null || !context.mounted) return;
  try {
    await ref
        .read(gameEventRepositoryProvider)
        .add(
          gameId: game.id!,
          side: draft.side,
          kind: draft.kind,
          athleteId: draft.athleteId,
          relatedAthleteId: draft.relatedId,
          penalty: draft.penalty,
        );
    HapticFeedback.mediumImpact();
    _refreshAfterEvent(ref, game, viewerTeamId);
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

/// Tira o último gol do lado [scoringSide] (o "−" do placar). Sem lance de
/// gol para apagar, devolve `false` (o placar é corrigido à mão).
Future<bool> removeLastGoal(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String viewerTeamId,
  required GameSide scoringSide,
}) async {
  final events = await ref.read(gameEventsProvider(game.id!).future);
  final last = events.reversed
      .where((event) => event.scoringSide == scoringSide)
      .firstOrNull;
  if (last == null || !context.mounted) return false;
  final confirmed = await confirmDelete(
    context,
    title: 'Tirar o gol?',
    message:
        '${last.title} (${last.timeLabel}) sai do placar e '
        'da súmula.',
  );
  if (!confirmed || !context.mounted) return true;
  await _delete(context, ref, game, viewerTeamId, last);
  return true;
}

Future<void> _delete(
  BuildContext context,
  WidgetRef ref,
  Game game,
  String viewerTeamId,
  GameEvent event,
) async {
  try {
    await ref.read(gameEventRepositoryProvider).delete(event.id);
    _refreshAfterEvent(ref, game, viewerTeamId);
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

/// Compartilha o link público do jogo (quem não tem conta acompanha ao vivo
/// pelo site).
Future<void> shareLiveGame(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String viewerTeamId,
}) async {
  try {
    final url = await ref
        .read(gameEventRepositoryProvider)
        .publicLink(game.id!);
    final mine =
        ref.read(selectedTeamProvider).value?.name ??
        game.hostTeamName ??
        'Meu time';
    final title = '$mine × ${game.opponentNameFor(viewerTeamId)}';
    await ref.read(shareTextProvider)(
      'Acompanhe $title ao vivo no SportLeague: $url',
    );
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

/// Linha do tempo dos lances. Com o jogo rolando, busca de novo de tempos em
/// tempos (o adversário também lança). [limit] mostra só os últimos.
class LiveTimeline extends ConsumerStatefulWidget {
  const LiveTimeline({
    super.key,
    required this.game,
    required this.viewerTeamId,
    this.limit,
    this.onSeeAll,
  });

  final Game game;
  final String viewerTeamId;
  final int? limit;

  /// "Ver todos" quando há mais lances que [limit].
  final VoidCallback? onSeeAll;

  @override
  ConsumerState<LiveTimeline> createState() => _LiveTimelineState();
}

class _LiveTimelineState extends ConsumerState<LiveTimeline> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (widget.game.clock?.inPlay ?? false) {
        ref.invalidate(gameEventsProvider(widget.game.id!));
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = widget.game;
    final events = ref.watch(gameEventsProvider(game.id!));
    final isOwner = ref.watch(canManageTeamProvider);
    final mySide = viewerSide(game, widget.viewerTeamId);

    return events.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => TextButton.icon(
        onPressed: () => ref.invalidate(gameEventsProvider(game.id!)),
        icon: const Icon(Icons.refresh),
        label: const Text('Erro ao carregar os lances. Tentar novamente'),
      ),
      data: (events) {
        if (events.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nenhum lance ainda.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final newest = events.reversed.toList();
        final shown = switch (widget.limit) {
          final limit? when newest.length > limit => newest.take(limit),
          _ => newest,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final event in shown)
              _EventTile(
                event: event,
                mine: event.side == mySide,
                teamName: event.side == mySide
                    ? null
                    : game.opponentNameFor(widget.viewerTeamId),
                onComplete:
                    isOwner &&
                        game.id != null &&
                        canCompleteGameEvent(
                          game,
                          widget.viewerTeamId,
                          event,
                        ) &&
                        (event.kind.isScoring ||
                            event.kind == GameEventKind.substitution) &&
                        (event.needsAthlete || event.kind == GameEventKind.goal)
                    ? () => _complete(event)
                    : null,
                onDelete:
                    isOwner &&
                        canAddGameEvent(
                          game,
                          widget.viewerTeamId,
                          side: event.side,
                          kind: event.kind,
                        )
                    ? () => _confirmDelete(event)
                    : null,
              ),
            if (widget.onSeeAll != null &&
                widget.limit != null &&
                newest.length > widget.limit!)
              TextButton(
                onPressed: widget.onSeeAll,
                child: Text('Ver os ${newest.length} lances'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(GameEvent event) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Apagar o lance?',
      message:
          '${event.title} (${event.timeLabel})'
          '${event.kind.isScoring ? ' sai do placar e da súmula.' : ' sai da súmula.'}',
    );
    if (!confirmed || !mounted) return;
    await _delete(context, ref, widget.game, widget.viewerTeamId, event);
  }

  /// Completa autor e assistência (gol) ou quem entrou (substituição).
  Future<void> _complete(GameEvent event) async {
    final game = widget.game;
    // O time do lado do lance (o convidado não tem atletas).
    final teamId = event.side == GameSide.host
        ? game.teamId
        : game.opponentTeamId;
    if (teamId == null || teamId != widget.viewerTeamId) {
      showErrorSnackBar(context, 'Só o time do lance completa os atletas.');
      return;
    }
    final athletes = await ref.read(activeAthletesProvider(teamId).future);
    if (!mounted) return;
    final picked = await showAppSheet<(String, String?)>(
      context,
      builder: (_) => _PlayersSheet(
        title: event.kind == GameEventKind.ownGoal
            ? 'Quem fez o gol contra?'
            : event.kind == GameEventKind.substitution
            ? 'Quem saiu e quem entrou?'
            : 'Quem fez o gol?',
        athletes: athletes,
        firstLabel: event.kind == GameEventKind.substitution
            ? 'Saiu'
            : 'Gol de',
        secondLabel: switch (event.kind) {
          GameEventKind.goal => 'Assistência (opcional)',
          GameEventKind.substitution => 'Entrou',
          _ => null,
        },
        initialFirst: event.athleteId,
        initialSecond: event.relatedAthleteId,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await ref
          .read(gameEventRepositoryProvider)
          .complete(
            event.id,
            athleteId: picked.$1,
            relatedAthleteId: picked.$2,
          );
      _refreshAfterEvent(ref, game, widget.viewerTeamId);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.mine,
    this.teamName,
    this.onComplete,
    this.onDelete,
  });

  final GameEvent event;

  /// Lance do time de quem vê.
  final bool mine;

  /// Nome do adversário, nos lances dele.
  final String? teamName;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final detail = [
      ?teamName,
      ?event.detail,
      if (event.kind.isScoring && event.needsAthlete) 'Autor a completar',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: SizedBox(
        width: 100,
        child: Row(
          children: [
            // Tempo do jogo (pelo relógio: "1ºT") e, embaixo, a hora do
            // lance.
            SizedBox(
              width: 52,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.periodLabel case final period?)
                    Text(
                      period,
                      semanticsLabel: event.phase?.label,
                      // Do tamanho da hora, sem negrito.
                      style: theme.textTheme.labelSmall,
                    ),
                  Text(
                    event.timeLabel,
                    semanticsLabel: event.timeSemantics,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            CircleAvatar(
              radius: 14,
              backgroundColor: mine
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              child: Icon(
                event.kind.icon,
                size: 16,
                color:
                    event.kind.color ??
                    (mine
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        event.title,
        style: event.kind.isScoring
            ? const TextStyle(fontWeight: FontWeight.w700)
            : null,
      ),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: onComplete == null && onDelete == null
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Opções do lance',
              onSelected: (value) => switch (value) {
                'complete' => onComplete?.call(),
                _ => onDelete?.call(),
              },
              itemBuilder: (_) => [
                if (onComplete != null)
                  const PopupMenuItem(
                    value: 'complete',
                    child: ListTile(
                      leading: Icon(Icons.person_search_outlined),
                      title: Text('Escolher atletas'),
                    ),
                  ),
                if (onDelete != null)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Apagar lance'),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// O que o lançamento devolve.
class _EventDraft {
  const _EventDraft({
    required this.side,
    required this.kind,
    this.athleteId,
    this.relatedId,
    this.penalty = false,
  });

  final GameSide side;
  final GameEventKind kind;
  final String? athleteId;
  final String? relatedId;
  final bool penalty;
}

/// Lançamento de um lance: de qual time, o tipo e os atletas.
class _LiveEventSheet extends StatefulWidget {
  const _LiveEventSheet({
    required this.game,
    required this.viewerTeamId,
    required this.mySide,
    required this.athletes,
    required this.initialSide,
    this.initialKind,
  });

  final Game game;
  final String viewerTeamId;
  final GameSide mySide;

  /// Atletas do time de quem lança (o adversário lança os dele).
  final List<Athlete> athletes;
  final GameSide initialSide;
  final GameEventKind? initialKind;

  @override
  State<_LiveEventSheet> createState() => _LiveEventSheetState();
}

class _LiveEventSheetState extends State<_LiveEventSheet> {
  late GameSide _side = widget.initialSide;
  late GameEventKind? _kind = widget.initialKind;
  String? _athlete;
  String? _related;
  bool _penalty = false;

  /// Tipos que quem vê pode lançar deste lado.
  List<GameEventKind> get _kinds => [
    for (final kind in GameEventKind.values)
      if (canAddGameEvent(
        widget.game,
        widget.viewerTeamId,
        side: _side,
        kind: kind,
      ))
        kind,
  ];

  /// Os atletas só aparecem para o lado de quem lança (o outro time escolhe
  /// os dele; o convidado não tem lista).
  bool get _pickAthletes =>
      _side == widget.mySide && widget.athletes.isNotEmpty;

  String _sideName(GameSide side) => side == widget.mySide
      ? 'Meu time'
      : widget.game.opponentNameFor(widget.viewerTeamId);

  @override
  Widget build(BuildContext context) {
    final kinds = _kinds;
    final kind = _effectiveKind;
    String label(Athlete athlete) => [
      if (athlete.jerseyNumber case final number?) '$number',
      athlete.displayName,
    ].join(' · ');
    final otherSideKinds = GameEventKind.values.where(
      (kind) => canAddGameEvent(
        widget.game,
        widget.viewerTeamId,
        side: widget.mySide.other,
        kind: kind,
      ),
    );

    return AppSheet(
      title: kind == null ? 'Novo lance' : kind.label,
      message: switch (kind) {
        GameEventKind.ownGoal => 'O gol contra vale para o outro time.',
        final kind? when kind.isScoring && !_pickAthletes =>
          _side == widget.mySide
              ? null
              : 'O ${_sideName(_side)} escolhe o autor do gol no app dele.',
        _ => 'O minuto vem do relógio da partida.',
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (otherSideKinds.isNotEmpty) ...[
            SegmentedButton<GameSide>(
              segments: [
                for (final side in [widget.mySide, widget.mySide.other])
                  ButtonSegment(
                    value: side,
                    label: Text(
                      _sideName(side),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {_side},
              onSelectionChanged: (value) => setState(() {
                _side = value.single;
                _athlete = null;
                _related = null;
              }),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in kinds)
                ChoiceChip(
                  avatar: Icon(option.icon, size: 18, color: option.color),
                  label: Text(option.label),
                  selected: option == kind,
                  onSelected: (_) => setState(() {
                    _kind = option;
                    _related = null;
                    if (option != GameEventKind.goal) _penalty = false;
                  }),
                ),
            ],
          ),
          if (kind != null && _pickAthletes) ...[
            const SizedBox(height: 16),
            DropdownMenu<String?>(
              key: ValueKey('first-$kind-$_side'),
              expandedInsets: EdgeInsets.zero,
              label: Text(switch (kind) {
                GameEventKind.goal || GameEventKind.ownGoal => 'Gol de',
                GameEventKind.substitution => 'Saiu',
                GameEventKind.penaltySaved => 'Goleiro',
                _ => 'Atleta',
              }),
              onSelected: (value) => setState(() => _athlete = value),
              dropdownMenuEntries: [
                if (kind.isScoring)
                  const DropdownMenuEntry(
                    value: null,
                    label: 'Escolher depois',
                  ),
                for (final athlete in widget.athletes)
                  DropdownMenuEntry(value: athlete.id, label: label(athlete)),
              ],
            ),
            if (kind == GameEventKind.goal ||
                kind == GameEventKind.substitution) ...[
              const SizedBox(height: 16),
              DropdownMenu<String?>(
                key: ValueKey('second-$kind-$_side-$_athlete'),
                expandedInsets: EdgeInsets.zero,
                label: Text(
                  kind == GameEventKind.goal
                      ? 'Assistência (opcional)'
                      : 'Entrou',
                ),
                onSelected: (value) => setState(() => _related = value),
                dropdownMenuEntries: [
                  if (kind == GameEventKind.goal)
                    const DropdownMenuEntry(
                      value: null,
                      label: 'Sem assistência',
                    ),
                  for (final athlete in widget.athletes)
                    if (athlete.id != _athlete)
                      DropdownMenuEntry(
                        value: athlete.id,
                        label: label(athlete),
                      ),
                ],
              ),
            ],
          ],
          if (kind == GameEventKind.goal) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gol de pênalti'),
              value: _penalty,
              onChanged: (value) => setState(() => _penalty = value),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: _canSave
              ? () => Navigator.of(context).pop(
                  _EventDraft(
                    side: _side,
                    kind: kind!,
                    athleteId: _athlete,
                    relatedId: _related,
                    penalty: _penalty,
                  ),
                )
              : null,
          icon: Icon(kind?.icon ?? Icons.add),
          label: const Text('Lançar'),
        ),
        const SheetBackButton(),
      ],
    );
  }

  /// Gols podem ficar sem autor; os outros lances do próprio time pedem o
  /// atleta (e a substituição, quem entrou).
  /// O tipo escolhido, se ainda vale para o lado escolhido.
  GameEventKind? get _effectiveKind => _kinds.contains(_kind) ? _kind : null;

  bool get _canSave {
    final kind = _effectiveKind;
    if (kind == null) return false;
    if (kind.isScoring || !_pickAthletes) return true;
    if (_athlete == null) return false;
    return kind != GameEventKind.substitution || _related != null;
  }
}

/// Escolha de um ou dois atletas (completar um lance).
class _PlayersSheet extends StatefulWidget {
  const _PlayersSheet({
    required this.title,
    required this.athletes,
    required this.firstLabel,
    this.secondLabel,
    this.initialFirst,
    this.initialSecond,
  });

  final String title;
  final List<Athlete> athletes;
  final String firstLabel;
  final String? secondLabel;
  final String? initialFirst;
  final String? initialSecond;

  @override
  State<_PlayersSheet> createState() => _PlayersSheetState();
}

class _PlayersSheetState extends State<_PlayersSheet> {
  late String? _first = widget.initialFirst;
  late String? _second = widget.initialSecond;

  @override
  Widget build(BuildContext context) {
    String label(Athlete athlete) => [
      if (athlete.jerseyNumber case final number?) '$number',
      athlete.displayName,
    ].join(' · ');
    final secondLabel = widget.secondLabel;
    return AppSheet(
      title: widget.title,
      message: 'Fica na súmula do jogo.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownMenu<String>(
            expandedInsets: EdgeInsets.zero,
            label: Text(widget.firstLabel),
            initialSelection: _first,
            onSelected: (value) => setState(() => _first = value),
            dropdownMenuEntries: [
              for (final athlete in widget.athletes)
                DropdownMenuEntry(value: athlete.id!, label: label(athlete)),
            ],
          ),
          if (secondLabel != null) ...[
            const SizedBox(height: 16),
            DropdownMenu<String?>(
              key: ValueKey('second-$_first'),
              expandedInsets: EdgeInsets.zero,
              label: Text(secondLabel),
              initialSelection: _second == _first ? null : _second,
              onSelected: (value) => setState(() => _second = value),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'Ninguém'),
                for (final athlete in widget.athletes)
                  if (athlete.id != _first)
                    DropdownMenuEntry(value: athlete.id, label: label(athlete)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: _first == null
              ? null
              : () =>
                    Navigator.of(context)
                        .pop((_first!, _second == _first ? null : _second)),
          icon: const Icon(Icons.check),
          label: const Text('Salvar'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}
