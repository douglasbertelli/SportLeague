import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/game_repository.dart';
import '../domain/game.dart';

/// "BAR" para "Barcelona": as 3 primeiras letras do nome, em maiúsculas.
String teamCode(String name) {
  final letters = name.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ0-9]'), '');
  final code = letters.length <= 3 ? letters : letters.substring(0, 3);
  return code.toUpperCase();
}

/// Ações do menu ⋮ do card.
enum _GameAction { edit, accept, decline, cancel }

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

  List<_GameAction> _actions() {
    final isHost = _game.isHostedBy(widget.viewerTeamId);
    return switch (_game.status) {
      GameStatus.canceled => const [],
      GameStatus.pending when isHost => const [
        _GameAction.edit,
        _GameAction.cancel,
      ],
      // Aceitar e Recusar ficam à vista no card (_canRespond).
      GameStatus.pending => const [],
      GameStatus.scheduled when isHost => const [
        _GameAction.edit,
        _GameAction.cancel,
      ],
      // O adversário cancela um marcado que ainda não aconteceu.
      GameStatus.scheduled when widget.stage == GameStage.scheduled => const [
        _GameAction.cancel,
      ],
      GameStatus.scheduled => const [],
    };
  }

  Future<void> _run(_GameAction action) async {
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
    final actions = _actions();
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
                    : PopupMenuButton<_GameAction>(
                        tooltip: 'Ações do amistoso',
                        icon: Icon(Icons.more_vert, color: colors.primary),
                        onSelected: _run,
                        itemBuilder: (_) => [
                          for (final action in actions)
                            PopupMenuItem(
                              value: action,
                              child: Text(switch (action) {
                                _GameAction.edit => 'Editar',
                                _GameAction.accept => 'Aceitar',
                                _GameAction.decline => 'Recusar',
                                _GameAction.cancel => 'Cancelar amistoso',
                              }),
                            ),
                        ],
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
