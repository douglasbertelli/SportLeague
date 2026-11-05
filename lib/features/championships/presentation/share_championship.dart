import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/presentation/share_result.dart'
    show capturePng, shareImageProvider;
import '../../teams/presentation/team_logo.dart';
import '../domain/championship.dart';
import '../domain/championship_rules.dart';

/// Mostra a prévia do campeonato como imagem (classificação ou final e, se
/// acabou, o campeão) e, no Compartilhar, manda para o app escolhido.
Future<void> shareChampionship(
  BuildContext context,
  WidgetRef ref, {
  required Championship championship,
  required List<ChampionshipTeam> teams,
  required List<ChampionshipMatch> matches,
}) async {
  final boundary = GlobalKey();
  final champion = championOf(championship, teams, matches);
  final text = champion == null
      ? '${championship.name} · ${championship.modality.label}'
      : '$champion é campeão do ${championship.name}!';

  await showAppSheet<void>(
    context,
    builder: (sheetContext) => AppSheet(
      title: 'Compartilhar campeonato',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: FittedBox(
            child: RepaintBoundary(
              key: boundary,
              child: ChampionshipShareCard(
                championship: championship,
                teams: teams,
                matches: matches,
              ),
            ),
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: () async {
            final png = await capturePng(boundary);
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

/// O campeão: o vencedor da final ou o líder dos pontos corridos (com o
/// campeonato encerrado). Nulo enquanto não acabou.
String? championOf(
  Championship championship,
  List<ChampionshipTeam> teams,
  List<ChampionshipMatch> matches,
) => championEntry(championship, teams, matches)?.name;

ChampionshipTeam? championEntry(
  Championship championship,
  List<ChampionshipTeam> teams,
  List<ChampionshipMatch> matches,
) {
  if (championship.status != ChampionshipStatus.finished) return null;
  final byId = {for (final t in teams) t.id: t};
  if (championship.format == ChampionshipFormat.league) {
    final ids = [
      for (final t in teams)
        if (t.status == EntryStatus.accepted) t.id,
    ];
    final names = {for (final t in teams) t.id: t.name};
    final table = standings(ids, matches, names: names);
    return table.isEmpty ? null : byId[table.first.teamId];
  }
  final finalMatch = finalOf(matches);
  return byId[finalMatch?.winnerId];
}

/// A final do mata-mata (o jogo da última fase); nula sem mata-mata.
ChampionshipMatch? finalOf(List<ChampionshipMatch> matches) {
  final knockout = matches.where((m) => m.stage == MatchStage.knockout);
  if (knockout.isEmpty) return null;
  final lastRound = knockout.map((m) => m.round).reduce(max);
  return knockout.firstWhere((m) => m.round == lastRound);
}

/// O campeonato como cartão para as redes (360×450, 4:5): o nome, o
/// campeão (se acabou) e a classificação (pontos corridos e grupos) ou a
/// final (mata-mata), com a marca do app.
class ChampionshipShareCard extends StatelessWidget {
  const ChampionshipShareCard({
    super.key,
    required this.championship,
    required this.teams,
    required this.matches,
  });

  static const size = Size(360, 450);

  final Championship championship;
  final List<ChampionshipTeam> teams;
  final List<ChampionshipMatch> matches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final champion = championEntry(championship, teams, matches);
    final byId = {for (final t in teams) t.id: t};
    final names = {for (final t in teams) t.id: t.name};
    final finalMatch = finalOf(matches);
    final groupsRunning =
        championship.format == ChampionshipFormat.groups &&
        !matches.any((m) => m.stage == MatchStage.knockout);

    final Widget body;
    if (championship.format == ChampionshipFormat.league) {
      final ids = [
        for (final t in teams)
          if (t.status == EntryStatus.accepted) t.id,
      ];
      body = _MiniTable(
        rows: standings(ids, matches, names: names).take(8).toList(),
        teams: byId,
      );
    } else if (groupsRunning) {
      final labels = groupLabels.take(championship.groupCount!).toList();
      // Até 4 grupos cabem; com mais, só os líderes de cada um.
      final perGroup = labels.length <= 2 ? 4 : (labels.length <= 4 ? 2 : 1);
      body = Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final label in labels)
            SizedBox(
              width: labels.length == 1 ? 312 : 150,
              child: _MiniTable(
                title: 'Grupo $label',
                compact: true,
                rows: standings(
                  [
                    for (final t in teams)
                      if (t.groupLabel == label) t.id,
                  ],
                  matches.where((m) => m.groupLabel == label),
                  names: names,
                ).take(perGroup).toList(),
                teams: byId,
              ),
            ),
        ],
      );
    } else if (finalMatch != null) {
      body = _FinalLine(match: finalMatch, teams: byId);
    } else {
      body = const SizedBox.shrink();
    }

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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      championship.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text(
                '${championship.modality.label} · ${championship.format.label}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (champion != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      TeamLogo.url(logoUrl: champion.logoUrl, radius: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CAMPEÃO',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onPrimaryContainer,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              champion.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: ClipRect(
                  child: Align(alignment: Alignment.topCenter, child: body),
                ),
              ),
              const SizedBox(height: 8),
              const Center(child: AppLogo(width: 96)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTable extends StatelessWidget {
  const _MiniTable({
    required this.rows,
    required this.teams,
    this.title,
    this.compact = false,
  });

  final List<StandingRow> rows;
  final Map<String, ChampionshipTeam> teams;
  final String? title;

  /// Nos grupos lado a lado: só a posição, o time e os pontos.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final header = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final cell = theme.textTheme.bodyMedium;
    Widget number(String text, TextStyle? style) => SizedBox(
      width: 28,
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
    final columns = compact ? ['P'] : ['P', 'J', 'V', 'SG'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title case final title?)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
        Row(
          children: [
            const SizedBox(width: 20),
            Expanded(child: Text('Time', style: header)),
            for (final column in columns) number(column, header),
          ],
        ),
        for (final (index, row) in rows.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${index + 1}',
                    style: cell?.copyWith(
                      color: index == 0 ? colors.primary : null,
                      fontWeight: index == 0 ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                TeamLogo.url(logoUrl: teams[row.teamId]?.logoUrl, radius: 9),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    teams[row.teamId]?.name ?? '',
                    style: cell,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                number(
                  '${row.points}',
                  cell?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (!compact) ...[
                  number('${row.played}', cell),
                  number('${row.wins}', cell),
                  number(
                    row.goalDifference > 0
                        ? '+${row.goalDifference}'
                        : '${row.goalDifference}',
                    cell,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A final: os dois times e o placar (com os pênaltis).
class _FinalLine extends StatelessWidget {
  const _FinalLine({required this.match, required this.teams});

  final ChampionshipMatch match;
  final Map<String, ChampionshipTeam> teams;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = teams[match.homeId];
    final away = teams[match.awayId];

    Widget side(ChampionshipTeam? team) => Expanded(
      child: Column(
        children: [
          TeamLogo.url(logoUrl: team?.logoUrl, radius: 26),
          const SizedBox(height: 6),
          Text(
            team?.name ?? 'A definir',
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Column(
      children: [
        Text('FINAL', style: theme.textTheme.labelLarge),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            side(home),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                children: [
                  Text(
                    match.hasScore
                        ? '${match.homeScore} × ${match.awayScore}'
                        : '×',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (match.homePenalties != null)
                    Text(
                      'pênaltis ${match.homePenalties} × '
                      '${match.awayPenalties}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            side(away),
          ],
        ),
      ],
    );
  }
}
