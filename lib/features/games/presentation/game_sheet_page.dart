import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../../teams/data/team_repository.dart';
import '../data/player_stats_repository.dart';
import '../domain/game.dart';
import '../domain/player_stats.dart';
import 'game_card.dart';

/// Abre a súmula do jogo, do ponto de vista do time [viewerTeamId].
Future<void> openGameSheet(
  BuildContext context, {
  required Game game,
  required String viewerTeamId,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => GameSheetPage(game: game, viewerTeamId: viewerTeamId),
  ),
);

/// Se o time ainda pode lançar a súmula: jogo marcado que começa em até uma
/// hora (ou já começou), como no banco.
bool canEditGameSheet(Game game, {DateTime? now}) =>
    game.status == GameStatus.scheduled &&
    !game.scheduledAt.isAfter(
      (now ?? DateTime.now()).add(const Duration(hours: 1)),
    );

/// Súmula do jogo: quem jogou em cada time, gols, assistências, cartões e o
/// craque. O time ativo lança ou corrige os dados dos próprios atletas.
class GameSheetPage extends ConsumerWidget {
  const GameSheetPage({
    super.key,
    required this.game,
    required this.viewerTeamId,
  });

  final Game game;
  final String viewerTeamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(gameStatsProvider(game.id!));
    final myName =
        ref.watch(selectedTeamProvider).value?.name ??
        (game.isHostedBy(viewerTeamId) ? game.hostTeamName : null) ??
        'Seu time';
    final opponentId = game.opponentTeamIdFor(viewerTeamId);
    // Fotos dos atletas (bucket privado: as do adversário só aparecem para
    // quem tem acesso; senão fica a inicial).
    final photos = <String, String>{
      for (final teamId in [viewerTeamId, ?opponentId])
        for (final athlete
            in ref.watch(teamAthletesProvider(teamId)).value ??
                const <Athlete>[])
          athlete.id!: ?athlete.photoUrl,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Súmula')),
      floatingActionButton: canEditGameSheet(game)
          ? FloatingActionButton.extended(
              heroTag: 'edit-sheet',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TeamSheetEditorPage(game: game, teamId: viewerTeamId),
                ),
              ),
              icon: const Icon(Icons.edit_note),
              label: const Text('Lançar dados'),
            )
          : null,
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(gameStatsProvider(game.id!)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar a súmula. Tentar novamente'),
          ),
        ),
        data: (stats) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text(
              '${formatGameDay(game.scheduledAt)} às '
              '${formatGameTime(game.scheduledAt)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            _TeamSection(
              title: myName,
              rows: [
                for (final row in stats)
                  if (row.teamId == viewerTeamId) row,
              ],
              photos: photos,
              emptyMessage: canEditGameSheet(game)
                  ? 'Ninguém lançado ainda. Toque em "Lançar dados".'
                  : 'Nenhum dado lançado.',
            ),
            // Adversário da plataforma: a parte que ele lançou.
            if (opponentId != null)
              _TeamSection(
                title: game.opponentNameFor(viewerTeamId),
                rows: [
                  for (final row in stats)
                    if (row.teamId == opponentId) row,
                ],
                photos: photos,
                emptyMessage: 'O adversário ainda não lançou os dados.',
              ),
          ],
        ),
      ),
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.title,
    required this.rows,
    required this.emptyMessage,
    required this.photos,
  });

  final String title;
  final List<PlayerGameStats> rows;

  /// URL da foto por atleta.
  final Map<String, String> photos;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...rows]
      ..sort((a, b) {
        final byGoals = b.goals.compareTo(a.goals);
        return byGoals != 0
            ? byGoals
            : (a.athleteName ?? '').compareTo(b.athleteName ?? '');
      });
    final goals = rows.fold(0, (sum, row) => sum + row.goals);

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (rows.isNotEmpty)
                Text(
                  '${rows.length} ${rows.length == 1 ? 'jogador' : 'jogadores'}'
                  ' · $goals ${goals == 1 ? 'gol' : 'gols'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(
              emptyMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final row in sorted)
                    ListTile(
                      dense: true,
                      leading: AthleteAvatar(
                        name: row.athleteName ?? 'Atleta',
                        photoUrl: photos[row.athleteId],
                      ),
                      title: Text(
                        [
                          if (row.jerseyNumber case final number?) '$number',
                          row.athleteName ?? 'Atleta',
                        ].join(' · '),
                      ),
                      subtitle: switch (statsLine(row)) {
                        '' => null,
                        final line => Text(line),
                      },
                      trailing: row.bestPlayer
                          ? Tooltip(
                              message: 'Craque do jogo',
                              child: Icon(
                                Icons.star,
                                color: theme.colorScheme.primary,
                                semanticLabel: 'Craque do jogo',
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "2 gols · 1 assistência · 1 amarelo · vermelho"; vazio se só jogou.
String statsLine(PlayerGameStats row) => [
  if (row.goals > 0) '${row.goals} ${row.goals == 1 ? 'gol' : 'gols'}',
  if (row.assists > 0)
    '${row.assists} ${row.assists == 1 ? 'assistência' : 'assistências'}',
  if (row.yellowCards > 0)
    '${row.yellowCards} ${row.yellowCards == 1 ? 'amarelo' : 'amarelos'}',
  if (row.redCard) 'vermelho',
].join(' · ');

/// Lançar a súmula do time: marca quem jogou e, para cada um, gols,
/// assistências, cartões e o craque do jogo.
class TeamSheetEditorPage extends ConsumerStatefulWidget {
  const TeamSheetEditorPage({
    super.key,
    required this.game,
    required this.teamId,
  });

  final Game game;
  final String teamId;

  @override
  ConsumerState<TeamSheetEditorPage> createState() =>
      _TeamSheetEditorPageState();
}

class _TeamSheetEditorPageState extends ConsumerState<TeamSheetEditorPage> {
  /// Linhas por atleta; ausente = não jogou. Preenchido na primeira carga.
  Map<String, PlayerGameStats>? _rows;
  bool _saving = false;

  PlayerGameStats _blank(Athlete athlete) => PlayerGameStats(
    gameId: widget.game.id!,
    teamId: widget.teamId,
    athleteId: athlete.id!,
  );

  void _update(String athleteId, PlayerGameStats row) =>
      setState(() => _rows![athleteId] = row);

  void _setBest(String athleteId) => setState(() {
    final rows = _rows!;
    final wasBest = rows[athleteId]?.bestPlayer ?? false;
    for (final MapEntry(:key, :value) in rows.entries.toList()) {
      rows[key] = value.copyWith(bestPlayer: false);
    }
    final row = rows[athleteId];
    if (!wasBest && row != null) {
      rows[athleteId] = row.copyWith(bestPlayer: true);
    }
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(playerStatsRepositoryProvider)
          .saveTeamSheet(
            gameId: widget.game.id!,
            teamId: widget.teamId,
            rows: _rows!.values.toList(),
          );
      ref
        ..invalidate(gameStatsProvider(widget.game.id!))
        ..invalidate(teamPlayerTotalsProvider(widget.teamId));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final athletes = ref.watch(teamAthletesProvider(widget.teamId));
    final stats = ref.watch(gameStatsProvider(widget.game.id!));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lançar dados'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              // O tema deixa os botões na largura toda; na barra, não.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _rows == null || _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ),
        ],
      ),
      body: switch ((athletes, stats)) {
        (AsyncValue(value: final athletes?), AsyncValue(value: final stats?)) =>
          _editor(context, athletes, stats),
        (AsyncValue(hasError: true), _) ||
        (_, AsyncValue(hasError: true)) => Center(
          child: TextButton.icon(
            onPressed: () => ref
              ..invalidate(teamAthletesProvider(widget.teamId))
              ..invalidate(gameStatsProvider(widget.game.id!)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar. Tentar novamente'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _editor(
    BuildContext context,
    List<Athlete> athletes,
    List<PlayerGameStats> stats,
  ) {
    final rows = _rows ??= {
      for (final row in stats)
        if (row.teamId == widget.teamId) row.athleteId: row,
    };
    final theme = Theme.of(context);
    if (athletes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'O time não tem atletas cadastrados. Cadastre na aba Atletas.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Marque quem jogou e lance o que cada um fez. A estrela escolhe o '
          'craque do jogo.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final athlete in athletes)
          _AthleteRow(
            athlete: athlete,
            row: rows[athlete.id],
            onPlayed: (played) => setState(() {
              if (played) {
                rows[athlete.id!] = _blank(athlete);
              } else {
                rows.remove(athlete.id);
              }
            }),
            onChanged: (row) => _update(athlete.id!, row),
            onBest: () => _setBest(athlete.id!),
          ),
      ],
    );
  }
}

class _AthleteRow extends StatelessWidget {
  const _AthleteRow({
    required this.athlete,
    required this.row,
    required this.onPlayed,
    required this.onChanged,
    required this.onBest,
  });

  final Athlete athlete;

  /// Nulo quando não jogou.
  final PlayerGameStats? row;
  final ValueChanged<bool> onPlayed;
  final ValueChanged<PlayerGameStats> onChanged;
  final VoidCallback onBest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = this.row;
    final name = [
      if (athlete.jerseyNumber case final number?) '$number',
      athlete.displayName,
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            CheckboxListTile(
              value: row != null,
              onChanged: (value) => onPlayed(value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(
                children: [
                  AthleteAvatar(name: athlete.displayName, photoUrl: athlete.photoUrl),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name)),
                ],
              ),
              subtitle: row == null ? const Text('Não jogou') : null,
              secondary: row == null
                  ? null
                  : IconButton(
                      tooltip: row.bestPlayer
                          ? 'Craque do jogo'
                          : 'Escolher como craque',
                      isSelected: row.bestPlayer,
                      icon: const Icon(Icons.star_border),
                      selectedIcon: Icon(
                        Icons.star,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: onBest,
                    ),
            ),
            if (row != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Counter(
                      label: 'Gols',
                      value: row.goals,
                      onChanged: (value) =>
                          onChanged(row.copyWith(goals: value)),
                    ),
                    _Counter(
                      label: 'Assist.',
                      value: row.assists,
                      onChanged: (value) =>
                          onChanged(row.copyWith(assists: value)),
                    ),
                    _Counter(
                      label: 'Amarelos',
                      value: row.yellowCards,
                      max: 2,
                      onChanged: (value) =>
                          onChanged(row.copyWith(yellowCards: value)),
                    ),
                    FilterChip(
                      label: const Text('Vermelho'),
                      selected: row.redCard,
                      onSelected: (value) =>
                          onChanged(row.copyWith(redCard: value)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Gols  −  2  +".
class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 99,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        IconButton(
          tooltip: 'Menos ${label.toLowerCase()}',
          visualDensity: VisualDensity.compact,
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        Text('$value', style: theme.textTheme.titleMedium),
        IconButton(
          tooltip: 'Mais ${label.toLowerCase()}',
          visualDensity: VisualDensity.compact,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
      ],
    );
  }
}

/// Depois de um gol no placar ao vivo, pergunta quem fez e quem deu a
/// assistência. Pular deixa para a súmula.
Future<void> askGoalScorer(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String teamId,
}) async {
  final athletes = await ref.read(teamAthletesProvider(teamId).future);
  if (athletes.isEmpty || !context.mounted) return;
  final picked = await showAppSheet<(String, String?)>(
    context,
    builder: (_) => _GoalScorerSheet(athletes: athletes),
  );
  if (picked == null || !context.mounted) return;
  try {
    await ref
        .read(playerStatsRepositoryProvider)
        .addGoal(
          gameId: game.id!,
          teamId: teamId,
          scorerId: picked.$1,
          assistId: picked.$2,
        );
    ref
      ..invalidate(gameStatsProvider(game.id!))
      ..invalidate(teamPlayerTotalsProvider(teamId));
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

class _GoalScorerSheet extends StatefulWidget {
  const _GoalScorerSheet({required this.athletes});

  final List<Athlete> athletes;

  @override
  State<_GoalScorerSheet> createState() => _GoalScorerSheetState();
}

class _GoalScorerSheetState extends State<_GoalScorerSheet> {
  String? _scorer;
  String? _assist;

  @override
  Widget build(BuildContext context) {
    String label(Athlete athlete) => [
      if (athlete.jerseyNumber case final number?) '$number',
      athlete.displayName,
    ].join(' · ');

    return AppSheet(
      title: 'Quem fez o gol?',
      message: 'Fica na súmula do jogo. Dá para corrigir depois.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownMenu<String>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('Gol de'),
            onSelected: (value) => setState(() => _scorer = value),
            dropdownMenuEntries: [
              for (final athlete in widget.athletes)
                DropdownMenuEntry(value: athlete.id!, label: label(athlete)),
            ],
          ),
          const SizedBox(height: 16),
          DropdownMenu<String?>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('Assistência (opcional)'),
            initialSelection: null,
            onSelected: (value) => setState(() => _assist = value),
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: null, label: 'Sem assistência'),
              for (final athlete in widget.athletes)
                if (athlete.id != _scorer)
                  DropdownMenuEntry(value: athlete.id, label: label(athlete)),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: _scorer == null
              ? null
              : () => Navigator.of(context).pop((_scorer!, _assist)),
          icon: const Icon(Icons.sports_soccer),
          label: const Text('Salvar gol'),
        ),
        const SheetBackButton(label: 'Pular'),
      ],
    );
  }
}

/// Foto do atleta em círculo; sem foto (ou se a URL expirar), a inicial.
class AthleteAvatar extends StatelessWidget {
  const AthleteAvatar({
    super.key,
    required this.name,
    required this.photoUrl,
    this.radius = 18,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photoUrl = this.photoUrl;
    return CircleAvatar(
      radius: radius,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      onForegroundImageError: photoUrl == null ? null : (_, _) {},
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
    );
  }
}
