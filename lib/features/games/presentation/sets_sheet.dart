import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../sports/domain/sport_rules.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../data/game_repository.dart';
import '../domain/game.dart';

/// Lança os sets do vôlei (quem marcou o jogo). Com [requireComplete], só
/// salva a partida terminada (placar depois do jogo); sem, salva set a set
/// (placar ao vivo). Devolve os sets na visão de quem marcou, ou nulo se
/// voltar.
Future<List<(int, int)>?> showSetsSheet(
  BuildContext context, {
  required Game game,
  required String myTeam,
  required String opponent,
  required bool requireComplete,
}) => showSetsEditor(
  context,
  modality: game.modality,
  bestOf: game.bestOf,
  initial: game.setScores,
  firstName: myTeam,
  secondName: opponent,
  requireComplete: requireComplete,
);

/// Lança os sets de uma partida de vôlei da [modality] (jogo do time ou jogo
/// de campeonato): cada set é ([firstName], [secondName]). Com
/// [requireComplete], só devolve a partida terminada. Nulo se voltar.
Future<List<(int, int)>?> showSetsEditor(
  BuildContext context, {
  required Modality? modality,
  required int? bestOf,
  required List<(int, int)>? initial,
  required String firstName,
  required String secondName,
  required bool requireComplete,
}) => showAppSheet<List<(int, int)>>(
  context,
  builder: (_) => _SetsSheet(
    modality: modality,
    bestOf: bestOf,
    initial: initial,
    myTeam: firstName,
    opponent: secondName,
    requireComplete: requireComplete,
  ),
);

/// Salva os sets e atualiza as listas do time; mostra o erro se não der.
Future<bool> saveSets(
  BuildContext context,
  WidgetRef ref, {
  required Game game,
  required String teamId,
  required List<(int, int)> sets,
}) async {
  try {
    await ref.read(gameRepositoryProvider).setSets(game.id!, sets);
    ref
      ..invalidate(teamGamesProvider(teamId))
      ..invalidate(teamStatsProvider(teamId));
    return true;
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
    return false;
  }
}

class _SetsSheet extends StatefulWidget {
  const _SetsSheet({
    required this.modality,
    required this.bestOf,
    required this.initial,
    required this.myTeam,
    required this.opponent,
    required this.requireComplete,
  });

  final Modality? modality;
  final int? bestOf;
  final List<(int, int)>? initial;
  final String myTeam;
  final String opponent;
  final bool requireComplete;

  @override
  State<_SetsSheet> createState() => _SetsSheetState();
}

class _SetsSheetState extends State<_SetsSheet> {
  late final SportRules _rules = rulesForModality(widget.modality);
  late final SetRules _sets = _rules.sets!;
  late final Modality? _modality = widget.modality;
  late final int _bestOf =
      widget.bestOf ?? _sets.defaultBestOf[_modality] ?? 5;

  /// Um par de campos por set (time, adversário).
  late final List<(TextEditingController, TextEditingController)> _rows = [
    for (final (a, b) in widget.initial ?? const <(int, int)>[])
      (TextEditingController(text: '$a'), TextEditingController(text: '$b')),
  ];

  String? _error;

  @override
  void initState() {
    super.initState();
    if (_rows.isEmpty) _addSet();
  }

  @override
  void dispose() {
    for (final (a, b) in _rows) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  void _addSet() => setState(() {
    _rows.add((TextEditingController(), TextEditingController()));
    _error = null;
  });

  void _removeSet() => setState(() {
    final (a, b) = _rows.removeLast();
    a.dispose();
    b.dispose();
    _error = null;
  });

  /// Os sets digitados; nulo se algum campo está vazio.
  List<(int, int)>? _read() {
    final sets = <(int, int)>[];
    for (final (a, b) in _rows) {
      final mine = int.tryParse(a.text);
      final theirs = int.tryParse(b.text);
      if (mine == null || theirs == null) return null;
      sets.add((mine, theirs));
    }
    return sets;
  }

  void _submit() {
    final sets = _read();
    if (sets == null) {
      setState(() => _error = 'Preencha os pontos de cada set.');
      return;
    }
    final result = _sets.progress(sets, modality: _modality, bestOf: _bestOf);
    if (result == null) {
      setState(
        () => _error =
            'Algum set não terminou: cada set vai até '
            '${_sets.targetFor(_modality, 1, _bestOf)} pontos (o '
            'tie-break, até ${_sets.tieBreakPoints}), com '
            '${_sets.minLead} de diferença.',
      );
      return;
    }
    if (widget.requireComplete && !_sets.isOver(result, _bestOf)) {
      setState(
        () => _error =
            'A partida ainda não terminou: alguém precisa vencer '
            '${_sets.setsToWin(_bestOf)} sets.',
      );
      return;
    }
    Navigator.of(context).pop(sets);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = _rules.periods.names;

    Widget field(TextEditingController controller, String label) => Expanded(
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, counterText: ''),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 2,
        onChanged: (_) => setState(() => _error = null),
      ),
    );

    return AppSheet(
      title: 'Placar em sets',
      message:
          'Melhor de $_bestOf: vence quem fechar '
          '${_sets.setsToWin(_bestOf)} sets.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, (mine, theirs)) in _rows.indexed) ...[
            Text(
              index < names.length ? names[index] : '${index + 1}º set',
              style: theme.textTheme.titleSmall,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field(mine, widget.myTeam),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Text('×', style: theme.textTheme.titleLarge),
                ),
                field(theirs, widget.opponent),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (_rows.length < _bestOf)
                TextButton.icon(
                  onPressed: _addSet,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar set'),
                ),
              const Spacer(),
              if (_rows.length > 1)
                TextButton.icon(
                  onPressed: _removeSet,
                  icon: const Icon(Icons.remove),
                  label: const Text('Tirar o último'),
                ),
            ],
          ),
          if (_error case final error?)
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
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

/// Placar ao vivo do vôlei, set a set: o placar em sets, os sets já
/// lançados e, para quem marcou o jogo, o botão de lançar o set que
/// terminou.
class LiveSetsScore extends ConsumerStatefulWidget {
  const LiveSetsScore({
    super.key,
    required this.team,
    required this.game,
    required this.canEdit,
  });

  final Team team;
  final Game game;
  final bool canEdit;

  @override
  ConsumerState<LiveSetsScore> createState() => _LiveSetsScoreState();
}

class _LiveSetsScoreState extends ConsumerState<LiveSetsScore> {
  bool _saving = false;

  Future<void> _enter() async {
    final game = widget.game;
    final sets = await showSetsSheet(
      context,
      game: game,
      myTeam: widget.team.name,
      opponent: game.opponentNameFor(widget.team.id!),
      requireComplete: false,
    );
    if (sets == null || !mounted) return;
    setState(() => _saving = true);
    await saveSets(
      context,
      ref,
      game: game,
      teamId: widget.team.id!,
      sets: sets,
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = widget.game;
    final viewer = widget.team.id!;
    final (mine, theirs) = game.scoreFor(viewer) ?? (0, 0);
    final sets = game.setScoresFor(viewer) ?? const <(int, int)>[];
    final names = game.rules.periods.names;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$mine × $theirs',
          textAlign: TextAlign.center,
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          'sets',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (sets.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final (index, (a, b)) in sets.indexed)
            Text(
              '${index < names.length ? names[index] : '${index + 1}º set'}: '
              '$a × $b',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
        ],
        if (widget.canEdit) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _saving ? null : _enter,
            icon: const Icon(Icons.scoreboard_outlined),
            label: Text(sets.isEmpty ? 'Lançar set' : 'Lançar ou corrigir set'),
          ),
        ],
      ],
    );
  }
}
