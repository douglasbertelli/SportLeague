import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/dispute_repository.dart';
import '../data/game_repository.dart';
import '../domain/game.dart';
import '../domain/score_dispute.dart';
import 'contest_score.dart';

/// "BAR" para "Barcelona": as 3 primeiras letras do nome, em maiúsculas.
String teamCode(String name) {
  final letters = name.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ0-9]'), '');
  final code = letters.length <= 3 ? letters : letters.substring(0, 3);
  return code.toUpperCase();
}

/// Ações do menu ⋮ do card.
enum _GameAction { edit, accept, decline, cancel, score, contest }

/// Card do amistoso do ponto de vista do time ativo ([viewerTeamId]): o time
/// ativo à esquerda, o adversário à direita, e abaixo data, hora, mando e
/// local. Ações (editar, aceitar, recusar, cancelar) ficam no menu ⋮.
class GameCard extends ConsumerStatefulWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.viewerTeamId,
    required this.stage,
  });

  final Game game;
  final String viewerTeamId;
  final GameStage stage;

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<GameCard> {
  bool _loading = false;

  Game get _game => widget.game;

  /// Já começou, mas ainda não terminou (fica em Marcados).
  bool get _inProgress =>
      _game.status == GameStatus.scheduled &&
      widget.stage == GameStage.scheduled &&
      !_game.scheduledAt.isAfter(DateTime.now());

  List<_GameAction> _actions(ScoreDispute? dispute) {
    final isHost = _game.isHostedBy(widget.viewerTeamId);
    return switch (_game.status) {
      GameStatus.canceled => const [],
      GameStatus.pending when isHost => const [
        _GameAction.edit,
        _GameAction.cancel,
      ],
      // Aceitar e Recusar ficam à vista no card (_canRespond).
      GameStatus.pending => const [],
      // Durante e depois do jogo, quem marcou lança (ou corrige) o placar.
      GameStatus.scheduled
          when isHost && (widget.stage == GameStage.played || _inProgress) =>
        const [_GameAction.score],
      GameStatus.scheduled when isHost => const [
        _GameAction.edit,
        _GameAction.cancel,
      ],
      // Com o jogo rolando, o adversário só acompanha.
      GameStatus.scheduled when _inProgress => const [],
      // O adversário cancela um marcado que ainda não aconteceu.
      GameStatus.scheduled when widget.stage == GameStage.scheduled => const [
        _GameAction.cancel,
      ],
      // Depois do jogo, o adversário contesta o placar (uma vez por vez).
      GameStatus.scheduled when _game.hasScore && dispute == null => const [
        _GameAction.contest,
      ],
      GameStatus.scheduled => const [],
    };
  }

  /// Ações do ⋮ num bottom sheet, cada uma com ícone.
  Future<void> _showActions(List<_GameAction> actions) async {
    final opponentName = _game.opponentNameFor(widget.viewerTeamId);
    final action = await showAppSheet<_GameAction>(
      context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AppSheet(
          title: 'Amistoso contra $opponentName',
          message:
              '${formatGameDay(_game.scheduledAt)} às '
              '${formatGameTime(_game.scheduledAt)}',
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (action) {
                    _GameAction.edit => Icons.edit_outlined,
                    _GameAction.accept => Icons.check_circle_outline,
                    _GameAction.decline => Icons.close,
                    _GameAction.cancel => Icons.event_busy,
                    _GameAction.score => Icons.scoreboard_outlined,
                    _GameAction.contest => Icons.report_outlined,
                  }),
                  iconColor: action == _GameAction.cancel ? colors.error : null,
                  textColor: action == _GameAction.cancel ? colors.error : null,
                  title: Text(switch (action) {
                    _GameAction.edit => 'Editar',
                    _GameAction.accept => 'Aceitar',
                    _GameAction.decline => 'Recusar',
                    _GameAction.cancel => 'Cancelar amistoso',
                    _GameAction.score =>
                      _game.hasScore ? 'Corrigir placar' : 'Lançar placar',
                    _GameAction.contest => 'Contestar placar',
                  }),
                  onTap: () => Navigator.of(context).pop(action),
                ),
            ],
          ),
          actions: const [SheetBackButton(label: 'Fechar')],
        );
      },
    );
    if (action != null && mounted) await _run(action);
  }

  /// Placar do ponto de vista de quem marcou (o único que lança).
  Future<void> _enterScore() async {
    final score = await showAppSheet<(int, int)>(
      context,
      builder: (_) => _ScoreSheet(
        myTeam:
            _game.hostTeamName ??
            ref.read(selectedTeamProvider).value?.name ??
            'Seu time',
        opponent: _game.opponent,
        initial: _game.hasScore
            ? (_game.teamScore!, _game.opponentScore!)
            : null,
      ),
    );
    if (score == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(gameRepositoryProvider)
          .setScore(_game.id!, teamScore: score.$1, opponentScore: score.$2);
      ref
        ..invalidate(teamGamesProvider(widget.viewerTeamId))
        ..invalidate(teamStatsProvider(widget.viewerTeamId));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// O adversário diz o placar na visão dele e o motivo; vai para quem
  /// marcou responder.
  Future<void> _contest() => contestScore(
    context,
    ref,
    game: _game,
    viewerTeamId: widget.viewerTeamId,
    myTeamName: ref.read(selectedTeamProvider).value?.name ?? 'Seu time',
  );

  /// Quem marcou responde à contestação.
  Future<void> _resolve(ScoreDispute dispute, {required bool accept}) async {
    final viewer = widget.viewerTeamId;
    if (!accept &&
        !await confirmAction(
          context,
          title: 'Manter o seu placar?',
          message:
              'A contestação de ${_game.opponentNameFor(viewer)} será '
              'recusada e o placar continua '
              '${_game.teamScore} × ${_game.opponentScore}.',
          confirmLabel: 'Manter',
          cancelLabel: 'Voltar',
        )) {
      return;
    }
    setState(() => _loading = true);
    try {
      await ref
          .read(disputeRepositoryProvider)
          .resolve(dispute.id!, accept: accept);
      ref
        ..invalidate(teamDisputesProvider(viewer))
        ..invalidate(teamGamesProvider(viewer))
        ..invalidate(teamStatsProvider(viewer));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(_GameAction action) async {
    if (action == _GameAction.score) return _enterScore();
    if (action == _GameAction.contest) return _contest();
    if (action == _GameAction.edit) {
      await context.push(Routes.editGame, extra: _game);
      return;
    }

    final opponentName = _game.opponentNameFor(widget.viewerTeamId);
    if (action != _GameAction.accept) {
      final decline = action == _GameAction.decline;
      final confirmed = await confirmAction(
        context,
        title: decline ? 'Recusar amistoso?' : 'Cancelar amistoso?',
        message: decline
            ? 'O amistoso contra $opponentName será recusado e irá para '
                  'Cancelados.'
            : 'O amistoso contra $opponentName será cancelado'
                  '${_game.opponentTeamId != null ? ' para os dois times' : ''}.',
        confirmLabel: decline ? 'Recusar' : 'Cancelar amistoso',
        confirmIcon: decline ? Icons.close : Icons.event_busy,
        cancelLabel: 'Voltar',
      );
      if (!confirmed) return;
    }

    setState(() => _loading = true);
    try {
      final repository = ref.read(gameRepositoryProvider);
      await (action == _GameAction.accept
          ? repository.accept(_game.id!)
          : repository.cancel(_game.id!));
      ref.invalidate(teamGamesProvider(widget.viewerTeamId));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// O adversário responde ao convite com botões no próprio card.
  bool get _canRespond =>
      _game.status == GameStatus.pending &&
      !_game.isHostedBy(widget.viewerTeamId);

  /// Linha de situação que o layout não tem e que não pode se perder.
  String? _statusLine() {
    final viewer = widget.viewerTeamId;
    final isHost = _game.isHostedBy(viewer);
    final opponentName = _game.opponentNameFor(viewer);
    return switch (_game.status) {
      GameStatus.pending when isHost => 'Aguardando $opponentName aceitar',
      GameStatus.pending => null,
      GameStatus.canceled => switch (_game.canceledByTeamId) {
        null => 'Cancelado: o adversário foi excluído',
        final id when id == viewer => 'Cancelado pelo seu time',
        _ => 'Cancelado por $opponentName',
      },
      GameStatus.scheduled => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final viewer = widget.viewerTeamId;
    final myTeam = ref.watch(selectedTeamProvider).value;
    final score = _game.scoreFor(viewer);
    // Contestação aberta deste jogo (feita pelo adversário).
    final dispute = ref
        .watch(teamDisputesProvider(viewer))
        .value
        ?.where((dispute) => dispute.gameId == _game.id)
        .firstOrNull;
    final actions = _actions(dispute);
    final statusLine = _statusLine();
    // Local cadastrado; jogos antigos só têm o texto digitado.
    final place = switch (_game.venue) {
      final venue? => '${venue.name} · ${venue.cityLine}',
      null => _game.location,
    };
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      color: colors.surface,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho: time ativo × adversário.
              ColoredBox(
                color: colors.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TeamSide(
                          name: myTeam?.name ?? '',
                          logoUrl: myTeam?.logoUrl,
                          city: myTeam?.city,
                          alignEnd: false,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: score == null
                            ? Icon(
                                Icons.close,
                                size: 28,
                                color: colors.onSurfaceVariant,
                                semanticLabel: 'contra',
                              )
                            : Text(
                                '${score.$1} × ${score.$2}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      Expanded(
                        child: _TeamSide(
                          name: _game.opponentNameFor(viewer),
                          logoUrl: _game.opponentLogoFor(viewer),
                          city: _game.opponentCityFor(viewer),
                          alignEnd: true,
                          // Time da plataforma: abre o perfil (capa,
                          // contatos e uniformes).
                          onTap: switch (_game.opponentTeamIdFor(viewer)) {
                            final teamId? => () => context.push(
                              Routes.teamProfile,
                              extra: teamId,
                            ),
                            null => null,
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Detalhes: data, hora, mando, local e situação.
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  actions.isEmpty ? 16 : 56,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _Detail(
                          icon: Icons.calendar_month_outlined,
                          text: formatGameDay(_game.scheduledAt),
                        ),
                        _Detail(
                          icon: Icons.schedule,
                          text: formatGameTime(_game.scheduledAt),
                        ),
                        _Detail(
                          icon: Icons.stadium_outlined,
                          text: _game.isHomeFor(viewer)
                              ? 'Mandante'
                              : 'Visitante',
                        ),
                        if (_game.modality case final modality?)
                          _Detail(
                            icon: Icons.sports_soccer,
                            text: modality.label,
                          ),
                      ],
                    ),
                    if (place != null) ...[
                      const SizedBox(height: 12),
                      _Detail(icon: Icons.location_on_outlined, text: place),
                    ],
                    if (statusLine != null) ...[
                      const SizedBox(height: 12),
                      Text(statusLine, style: mutedStyle),
                    ],
                    if (dispute != null) ...[
                      const SizedBox(height: 16),
                      _DisputeBox(
                        dispute: dispute,
                        isHost: _game.isHostedBy(viewer),
                        hostName: _game.isHostedBy(viewer)
                            ? myTeam?.name ?? 'Seu time'
                            : _game.opponentNameFor(viewer),
                        opponentName: _game.isHostedBy(viewer)
                            ? _game.opponentNameFor(viewer)
                            : myTeam?.name ?? 'Seu time',
                        loading: _loading,
                        onAnswer: (accept) => _resolve(dispute, accept: accept),
                      ),
                    ],
                    if (_canRespond) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(88, 48),
                                // Texto verde e borda um pouco mais escura
                                // que a padrão.
                                foregroundColor: colors.primary,
                                side: BorderSide(
                                  color: _darker(colors.outline),
                                ),
                              ),
                              onPressed: _loading
                                  ? null
                                  : () => _run(_GameAction.decline),
                              child: const Text('Recusar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(88, 48),
                              ),
                              onPressed: _loading
                                  ? null
                                  : () => _run(_GameAction.accept),
                              child: _loading
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Aceitar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: colors.surfaceContainerHigh,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                ),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Ações do amistoso',
                        icon: Icon(Icons.more_vert, color: colors.primary),
                        onPressed: () => _showActions(actions),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lado do cabeçalho: logo, sigla e cidade. O nome completo vai para a
/// acessibilidade.
class _TeamSide extends StatelessWidget {
  const _TeamSide({
    required this.name,
    required this.logoUrl,
    required this.city,
    required this.alignEnd,
    this.onTap,
  });

  final String name;
  final String? logoUrl;
  final String? city;
  final bool alignEnd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texts = Flexible(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            teamCode(name),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (city case final city?)
            Text(
              city,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
    final logo = TeamLogo.url(logoUrl: logoUrl, radius: 24);

    final side = Semantics(
      container: true,
      label: name,
      button: onTap != null,
      hint: onTap == null ? null : 'Ver perfil do time',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: alignEnd
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: alignEnd
            ? [texts, const SizedBox(width: 12), logo]
            : [logo, const SizedBox(width: 12), texts],
      ),
    );
    return switch (onTap) {
      final onTap? => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: side,
      ),
      null => side,
    };
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    );
  }
}

/// "12/03/2026".
String formatGameDay(DateTime date) =>
    '${_two(date.day)}/${_two(date.month)}/${date.year}';

/// "20:00".
String formatGameTime(DateTime date) =>
    '${_two(date.hour)}:${_two(date.minute)}';

String _two(int value) => value.toString().padLeft(2, '0');

/// [color] com a luminosidade um pouco menor (borda do Recusar).
Color _darker(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
}

/// Contestação aberta no card. Quem marcou vê o placar proposto e a
/// mensagem, e aceita ou mantém o dele; quem contestou vê que está
/// aguardando.
class _DisputeBox extends StatelessWidget {
  const _DisputeBox({
    required this.dispute,
    required this.isHost,
    required this.hostName,
    required this.opponentName,
    required this.loading,
    required this.onAnswer,
  });

  final ScoreDispute dispute;
  final bool isHost;
  final String hostName;
  final String opponentName;
  final bool loading;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    // Do ponto de vista de quem marcou: "Amigos 1 × 2 Real".
    final proposed =
        '$hostName ${dispute.teamScore} × ${dispute.opponentScore} '
        '$opponentName';

    // Quem contestou: o destaque fica na mensagem; abaixo, o que ele mandou.
    if (!isHost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DisputeSentBadge(hostName: hostName),
          const SizedBox(height: 8),
          Text('Placar enviado: $proposed', style: muted),
          const SizedBox(height: 4),
          Text('"${dispute.message}"', style: muted),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.report_outlined, size: 20, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$opponentName contestou o placar',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Placar para eles: $proposed', style: muted),
            const SizedBox(height: 4),
            Text('"${dispute.message}"', style: theme.textTheme.bodyMedium),
            if (isHost) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: loading ? null : () => onAnswer(false),
                      child: const Text('Manter o meu'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: loading ? null : () => onAnswer(true),
                      child: const Text('Aceitar placar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lança o placar: gols do time que marcou e do adversário.
class _ScoreSheet extends StatefulWidget {
  const _ScoreSheet({
    required this.myTeam,
    required this.opponent,
    required this.initial,
  });

  final String myTeam;
  final String opponent;
  final (int, int)? initial;

  @override
  State<_ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<_ScoreSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _mine = TextEditingController(text: widget.initial?.$1.toString());
  late final _theirs = TextEditingController(
    text: widget.initial?.$2.toString(),
  );

  @override
  void dispose() {
    _mine.dispose();
    _theirs.dispose();
    super.dispose();
  }

  String? _validate(String? value) =>
      int.tryParse(value ?? '') == null ? 'Informe os gols' : null;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((int.parse(_mine.text), int.parse(_theirs.text)));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController controller, String team) => Expanded(
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: team, counterText: ''),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 2,
        validator: _validate,
      ),
    );

    return AppSheet(
      title: 'Placar',
      message: 'Gols de cada time. Ele aparece no card e no perfil dos times.',
      body: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field(_mine, widget.myTeam),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Text(
                '×',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            field(_theirs, widget.opponent),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar placar'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}
