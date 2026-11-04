import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/player_stats_repository.dart';
import '../domain/game.dart';
import '../domain/player_stats.dart';
import 'game_card.dart' show formatGameDay;

/// Abre o compartilhamento do sistema com a imagem (WhatsApp, Instagram…).
/// Substituível nos testes.
final shareImageProvider =
    Provider<Future<void> Function(Uint8List png, String text)>(
      (ref) =>
          (png, text) async => SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(png, mimeType: 'image/png')],
              fileNameOverrides: const ['resultado.png'],
              text: text,
            ),
          ),
    );

/// Mostra a prévia do resultado do [game] como imagem e, no Compartilhar,
/// manda a imagem para o app que a pessoa escolher.
Future<void> shareGameResult(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String viewerTeamId,
  required Team? myTeam,
}) async {
  // Os gols de cada time, se a súmula foi lançada.
  List<PlayerGameStats> stats;
  try {
    stats = await ref.read(gameStatsProvider(game.id!).future);
  } catch (_) {
    stats = const [];
  }
  if (!context.mounted) return;

  final boundary = GlobalKey();
  final opponent = game.opponentNameFor(viewerTeamId);
  final (mine, theirs) = game.scoreFor(viewerTeamId)!;
  final text =
      '${myTeam?.name ?? 'Meu time'} $mine × $theirs $opponent '
      '· ${formatGameDay(game.scheduledAt)}';

  await showAppSheet<void>(
    context,
    builder: (sheetContext) => AppSheet(
      title: 'Compartilhar resultado',
      body: Center(
        // A prévia encolhe para caber; a imagem sai no tamanho real.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: FittedBox(
            child: RepaintBoundary(
              key: boundary,
              child: GameResultCard(
                game: game,
                viewerTeamId: viewerTeamId,
                myTeam: myTeam,
                stats: stats,
              ),
            ),
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: () async {
            final png = await _capture(boundary);
            if (png == null) {
              if (sheetContext.mounted) {
                showErrorSnackBar(
                  sheetContext,
                  'Não foi possível gerar a imagem.',
                );
              }
              return;
            }
            await ref.read(shareImageProvider)(png, text);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
          icon: const Icon(Icons.share_outlined),
          label: const Text('Compartilhar'),
        ),
        const SheetBackButton(label: 'Fechar'),
      ],
    ),
  );
}

/// A imagem PNG do que está dentro do [boundary], em alta resolução.
Future<Uint8List?> _capture(GlobalKey boundary) async {
  final render = boundary.currentContext?.findRenderObject();
  if (render is! RenderRepaintBoundary) return null;
  try {
    final image = await render.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// O resultado do jogo como cartão para as redes (360×450, 4:5): os dois
/// times com os logos, o placar, vitória/empate/derrota, quem fez os gols, o
/// craque e a marca do app.
class GameResultCard extends StatelessWidget {
  const GameResultCard({
    super.key,
    required this.game,
    required this.viewerTeamId,
    required this.myTeam,
    this.stats = const [],
  });

  static const size = Size(360, 450);

  final Game game;
  final String viewerTeamId;
  final Team? myTeam;
  final List<PlayerGameStats> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (mine, theirs) = game.scoreFor(viewerTeamId)!;
    final (outcome, outcomeColor) = switch (mine.compareTo(theirs)) {
      > 0 => ('VITÓRIA', colors.primary),
      < 0 => ('DERROTA', colors.error),
      _ => ('EMPATE', colors.onSurfaceVariant),
    };
    final venue = game.venue?.name ?? game.location;
    final myScorers = _scorers(stats.where((s) => s.teamId == viewerTeamId));
    final theirScorers = _scorers(stats.where((s) => s.teamId != viewerTeamId));
    final bestPlayer = stats
        .where((s) => s.teamId == viewerTeamId && s.bestPlayer)
        .firstOrNull;

    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                colors.primary.withValues(alpha: 0.28),
                colors.surface,
              ),
              colors.surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          child: Column(
            children: [
              Text(
                'AMISTOSO · ${formatGameDay(game.scheduledAt)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (venue != null) ...[
                const SizedBox(height: 2),
                Text(
                  venue,
                  style: muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Side(
                      name: myTeam?.name ?? 'Meu time',
                      logoUrl: myTeam?.logoUrl,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text(
                      '$mine × $theirs',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Side(
                      name: game.opponentNameFor(viewerTeamId),
                      logoUrl: game.opponentLogoFor(viewerTeamId),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: outcomeColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  outcome,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: outcomeColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Quem fez os gols, embaixo de cada time.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _ScorerList(myScorers)),
                    const SizedBox(width: 16),
                    Expanded(child: _ScorerList(theirScorers, alignEnd: true)),
                  ],
                ),
              ),
              if (bestPlayer?.athleteName case final name?) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star_rounded, size: 18, color: colors.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Craque do jogo: $name',
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              const AppLogo(width: 96),
            ],
          ),
        ),
      ),
    );
  }

  /// "Fulano (2)", na ordem de quem fez mais gols.
  static List<String> _scorers(Iterable<PlayerGameStats> stats) {
    final scorers = stats.where((s) => s.goals > 0).toList()
      ..sort((a, b) => b.goals.compareTo(a.goals));
    return [
      for (final s in scorers)
        '${s.athleteName ?? 'Atleta'}${s.goals > 1 ? ' (${s.goals})' : ''}',
    ];
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.name, required this.logoUrl});

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TeamLogo.url(logoUrl: logoUrl, radius: 32),
        const SizedBox(height: 8),
        Text(
          name,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ScorerList extends StatelessWidget {
  const _ScorerList(this.scorers, {this.alignEnd = false});

  final List<String> scorers;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = scorers.take(4).toList();
    final hidden = scorers.length - shown.length;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        for (final scorer in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: alignEnd ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Icon(
                  Icons.sports_soccer,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    scorer,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (hidden > 0)
          Text(
            '+$hidden',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
