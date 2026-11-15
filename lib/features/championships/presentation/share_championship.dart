import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/presentation/share_result.dart'
    show capturePng, shareImageProvider;
import '../../invites/data/invite_repository.dart' show shareTextProvider;
import '../../teams/presentation/team_logo.dart';
import '../data/championship_repository.dart';
import '../domain/championship.dart';
import '../domain/championship_rules.dart';

/// Link da página pública do campeonato no site (sem login).
String publicChampionshipUrl(String slug) => '${Env.siteUrl}/c/$slug';

/// Compartilhar o campeonato: o link público (página no site para quem não
/// tem conta: classificação, jogos e artilharia, sempre em dia) e a imagem
/// (classificação ou final e, se acabou, o campeão). O organizador liga,
/// desliga e troca o link aqui; [onChanged] avisa a tela para recarregar.
Future<void> shareChampionship(
  BuildContext context,
  WidgetRef ref, {
  required Championship championship,
  required List<ChampionshipTeam> teams,
  required List<ChampionshipMatch> matches,
  bool isOwner = false,
  VoidCallback? onChanged,
}) => showAppSheet<void>(
  context,
  builder: (_) => _ShareSheet(
    championship: championship,
    teams: teams,
    matches: matches,
    isOwner: isOwner,
    onChanged: onChanged,
  ),
);

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({
    required this.championship,
    required this.teams,
    required this.matches,
    required this.isOwner,
    this.onChanged,
  });

  final Championship championship;
  final List<ChampionshipTeam> teams;
  final List<ChampionshipMatch> matches;
  final bool isOwner;
  final VoidCallback? onChanged;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _boundary = GlobalKey();
  late var _enabled = widget.championship.publicEnabled;
  late var _slug = widget.championship.publicSlug;
  var _saving = false;

  Championship get _c => widget.championship;

  Future<void> _setPublic({required bool enabled, bool newLink = false}) async {
    setState(() => _saving = true);
    try {
      final slug = await ref
          .read(championshipRepositoryProvider)
          .setPublic(_c.id!, enabled: enabled, newLink: newLink);
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _slug = slug;
        });
      }
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _newLink() async {
    final confirmed = await confirmAction(
      context,
      title: 'Trocar o link?',
      message: 'O link atual para de funcionar. Mande o novo a quem acompanha.',
      confirmLabel: 'Trocar',
      confirmIcon: Icons.autorenew,
    );
    if (confirmed) await _setPublic(enabled: true, newLink: true);
  }

  Future<void> _shareImage() async {
    final champion = championOf(_c, widget.teams, widget.matches);
    final text = champion == null
        ? '${_c.name} · ${_c.modality.label}'
        : '$champion é campeão do ${_c.name}!';
    final png = await capturePng(_boundary);
    if (png == null) {
      if (mounted) {
        showErrorSnackBar(context, 'Não foi possível gerar a imagem.');
      }
      return;
    }
    await ref.read(shareImageProvider)(png, text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final slug = _slug;
    final url = _enabled && slug != null ? publicChampionshipUrl(slug) : null;
    // Antes da tabela não há imagem (nem classificação nem final).
    final hasImage = _c.status != ChampionshipStatus.draft;

    return AppSheet(
      title: 'Compartilhar campeonato',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Link público', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            url != null
                ? 'Quem tiver o link acompanha a classificação, os jogos e a '
                      'artilharia no site, sem precisar de conta.'
                : widget.isOwner
                ? 'Ligue para mandar um link a quem não usa o app. Só aparecem '
                      'os times, os jogos e os números do campeonato.'
                : 'O organizador ainda não ligou o link público.',
            style: muted,
          ),
          if (widget.isOwner) ...[
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                title: const Text('Link público'),
                subtitle: Text(
                  _enabled
                      ? 'Quem tiver o link vê'
                      : 'Desligado: o link não abre',
                ),
                value: _enabled,
                onChanged: _saving ? null : (on) => _setPublic(enabled: on),
              ),
            ),
          ],
          if (url != null) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Copiar link',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      showErrorSnackBar(context, 'Link copiado.');
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => ref.read(shareTextProvider)(
                'Acompanhe o ${_c.name} no SportLeague: $url',
              ),
              icon: const Icon(Icons.link),
              label: const Text('Compartilhar link'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ver página'),
                  ),
                ),
                if (widget.isOwner) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _newLink,
                      icon: const Icon(Icons.autorenew),
                      label: const Text('Trocar link'),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (hasImage) ...[
            const SizedBox(height: 24),
            Text('Imagem', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: ChampionshipShareCard(
                      championship: _c,
                      teams: widget.teams,
                      matches: widget.matches,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (hasImage)
          url == null
              ? FilledButton.icon(
                  onPressed: _shareImage,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Compartilhar imagem'),
                )
              : OutlinedButton.icon(
                  onPressed: _shareImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Compartilhar imagem'),
                ),
        const SheetBackButton(label: 'Fechar'),
      ],
    );
  }
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
