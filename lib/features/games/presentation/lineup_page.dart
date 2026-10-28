import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../data/lineup_repository.dart';
import '../domain/game.dart';
import 'game_card.dart';
import 'game_sheet_page.dart';

/// Abre a escalação do time [teamId] no jogo.
Future<void> openLineup(
  BuildContext context, {
  required Game game,
  required String teamId,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => LineupPage(game: game, teamId: teamId),
  ),
);

/// Escala de um atleta.
enum _Spot { starter, sub, out }

/// Escalação do time no jogo: titulares (quantos a modalidade põe em campo)
/// e reservas. O dono e o técnico montam; antes e durante o jogo.
class LineupPage extends ConsumerStatefulWidget {
  const LineupPage({super.key, required this.game, required this.teamId});

  final Game game;
  final String teamId;

  @override
  ConsumerState<LineupPage> createState() => _LineupPageState();
}

class _LineupPageState extends ConsumerState<LineupPage> {
  /// Escala de cada atleta; preenchida na primeira carga.
  Map<String, _Spot>? _spots;
  bool _saving = false;

  int get _maxStarters => startersFor(widget.game.modality);

  int _count(_Spot spot) =>
      _spots!.values.where((value) => value == spot).length;

  void _set(String athleteId, _Spot spot) {
    if (spot == _Spot.starter &&
        _spots![athleteId] != _Spot.starter &&
        _count(_Spot.starter) >= _maxStarters) {
      showErrorSnackBar(
        context,
        'Já são $_maxStarters titulares. Passe alguém para a reserva antes.',
      );
      return;
    }
    setState(() => _spots![athleteId] = spot);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(lineupRepositoryProvider)
          .saveTeam(
            gameId: widget.game.id!,
            teamId: widget.teamId,
            entries: [
              for (final MapEntry(key: athleteId, value: spot)
                  in _spots!.entries)
                if (spot != _Spot.out)
                  (
                    teamId: widget.teamId,
                    athleteId: athleteId,
                    starter: spot == _Spot.starter,
                  ),
            ],
          );
      ref.invalidate(gameLineupProvider(widget.game.id!));
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
    final lineup = ref.watch(gameLineupProvider(widget.game.id!));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escalação'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              // O tema deixa os botões na largura toda; na barra, não.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _spots == null || _saving ? null : _save,
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
      body: switch ((athletes, lineup)) {
        (
          AsyncValue(value: final athletes?),
          AsyncValue(value: final lineup?),
        ) =>
          _editor(context, athletes, lineup),
        (AsyncValue(hasError: true), _) ||
        (_, AsyncValue(hasError: true)) => Center(
          child: TextButton.icon(
            onPressed: () => ref
              ..invalidate(teamAthletesProvider(widget.teamId))
              ..invalidate(gameLineupProvider(widget.game.id!)),
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
    List<LineupEntry> lineup,
  ) {
    final theme = Theme.of(context);
    final spots = _spots ??= {
      for (final athlete in athletes)
        athlete.id!: switch (lineup
            .where((entry) => entry.athleteId == athlete.id)
            .firstOrNull) {
          final entry? => entry.starter ? _Spot.starter : _Spot.sub,
          null => _Spot.out,
        },
    };
    if (athletes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'O time não tem atletas cadastrados.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final starters = _count(_Spot.starter);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // Uma seção por escala, na ordem da súmula; o atleta muda de seção ao
    // trocar a escala.
    final sections = [
      (
        _Spot.starter,
        'Titulares',
        '$starters de $_maxStarters',
        'Nenhum titular escalado.',
      ),
      (
        _Spot.sub,
        'Reservas',
        '${_count(_Spot.sub)}',
        'Nenhum reserva escalado.',
      ),
      (_Spot.out, 'Fora', '${_count(_Spot.out)}', 'Todos foram escalados.'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          '${formatGameDay(widget.game.scheduledAt)} às '
          '${formatGameTime(widget.game.scheduledAt)} · '
          'x ${widget.game.opponentNameFor(widget.teamId)}',
          style: mutedStyle,
        ),
        for (final (spot, title, count, empty) in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(
                  count,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: spot == _Spot.starter && starters == _maxStarters
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!spots.containsValue(spot))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(empty, style: mutedStyle),
            ),
          for (final athlete in athletes)
            if (spots[athlete.id] == spot) _athleteCard(theme, athlete, spot),
        ],
      ],
    );
  }

  Widget _athleteCard(ThemeData theme, Athlete athlete, _Spot spot) => Card(
    // A chave mantém o card certo quando o atleta muda de seção.
    key: ValueKey(athlete.id),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          AthleteAvatar(name: athlete.name, photoUrl: athlete.photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (athlete.jerseyNumber case final number?) '$number',
                    athlete.name,
                  ].join(' · '),
                ),
                if (athlete.position case final position?)
                  Text(
                    position,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          SegmentedButton<_Spot>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: _Spot.starter, label: Text('Tit.')),
              ButtonSegment(value: _Spot.sub, label: Text('Res.')),
              ButtonSegment(value: _Spot.out, label: Text('Fora')),
            ],
            selected: {spot},
            onSelectionChanged: (selection) =>
                _set(athlete.id!, selection.single),
          ),
        ],
      ),
    ),
  );
}
