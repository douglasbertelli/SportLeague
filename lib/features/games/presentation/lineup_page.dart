import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../data/lineup_repository.dart';
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import '../domain/formation.dart';
import '../domain/game.dart';
import 'game_card.dart';
import 'game_sheet_page.dart';
import 'tactical_lineup.dart';

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

  /// Escalação no campo: a formação e quem está em cada posição.
  Formation? _formation;
  Map<int, String>? _placed;

  int get _maxStarters => startersFor(widget.game.modality);

  ({String gameId, String teamId}) get _key =>
      (gameId: widget.game.id!, teamId: widget.teamId);

  /// No campo, titular é quem tem posição; os outros vão para a reserva ou
  /// ficam fora.
  void _place(String athleteId, int slot) {
    final placed = _placed!;
    final from = placed.entries
        .where((entry) => entry.value == athleteId)
        .firstOrNull
        ?.key;
    final occupant = placed[slot];
    setState(() {
      if (from != null) {
        // Troca de posição com quem estava lá.
        if (occupant == null) {
          placed.remove(from);
        } else {
          placed[from] = occupant;
        }
      } else if (occupant != null) {
        // Quem saiu volta para a reserva.
        _spots![occupant] = _Spot.sub;
      }
      placed[slot] = athleteId;
      _spots![athleteId] = _Spot.starter;
    });
  }

  void _removeFromField(String athleteId) => setState(() {
    _placed!.removeWhere((_, id) => id == athleteId);
    _spots![athleteId] = _Spot.sub;
  });

  void _toggleReserve(String athleteId) => setState(
    () => _spots![athleteId] = _spots![athleteId] == _Spot.sub
        ? _Spot.out
        : _Spot.sub,
  );

  /// O administrador escolhe como a escalação abre no time.
  Future<void> _chooseStyle(LineupSettings settings) async {
    final style = await showAppSheet<LineupStyle>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Visualização da escalação',
        message: 'Vale para todos os jogos do time.',
        body: RadioGroup<LineupStyle>(
          groupValue: settings.style,
          onChanged: (value) => Navigator.of(sheetContext).pop(value),
          child: Column(
            children: [
              const RadioListTile<LineupStyle>(
                value: LineupStyle.list,
                title: Text('Lista (padrão)'),
                subtitle: Text('Titulares, reservas e fora'),
              ),
              RadioListTile<LineupStyle>(
                value: LineupStyle.field,
                title: Row(
                  children: [
                    const Text('Campo'),
                    if (!settings.fieldAvailable) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.workspace_premium_outlined,
                        size: 18,
                        color: Theme.of(sheetContext).colorScheme.tertiary,
                      ),
                    ],
                  ],
                ),
                subtitle: const Text(
                  'Formação e jogadores arrastados para as posições',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (style == null || style == settings.style || !mounted) return;
    if (style == LineupStyle.field && !settings.fieldAvailable) {
      await showPremiumSheet(context, PlanFeature.tacticalLineup);
      return;
    }
    try {
      await ref.read(lineupRepositoryProvider).setStyle(widget.teamId, style);
      // Recomeça a montagem no novo modo, com o que já foi escolhido.
      setState(() => _placed = null);
      ref.invalidate(lineupSettingsProvider(widget.teamId));
    } catch (error) {
      if (mounted && !handlePlanLimitError(context, error)) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    }
  }

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
    final repository = ref.read(lineupRepositoryProvider);
    final placed = _placed;
    final slotOf = {
      for (final MapEntry(key: slot, value: athleteId)
          in (placed ?? const <int, String>{}).entries)
        athleteId: slot,
    };
    try {
      if (placed != null) {
        await repository.saveFormation(
          gameId: widget.game.id!,
          teamId: widget.teamId,
          formation: _formation!.name,
        );
      }
      await repository.saveTeam(
        gameId: widget.game.id!,
        teamId: widget.teamId,
        entries: [
          for (final MapEntry(key: athleteId, value: spot) in _spots!.entries)
            if (spot != _Spot.out)
              (
                teamId: widget.teamId,
                athleteId: athleteId,
                starter: spot == _Spot.starter,
                slot: slotOf[athleteId],
              ),
        ],
      );
      ref
        ..invalidate(gameLineupProvider(widget.game.id!))
        ..invalidate(gameFormationProvider(_key));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted && !handlePlanLimitError(context, error)) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final athletes = ref.watch(teamAthletesProvider(widget.teamId));
    final lineup = ref.watch(gameLineupProvider(widget.game.id!));
    final settings = ref.watch(lineupSettingsProvider(widget.teamId));
    final formation = ref.watch(gameFormationProvider(_key));
    final isOwner =
        settings.value?.ownerId != null &&
        settings.value?.ownerId == ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escalação'),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Visualização da escalação',
              onPressed: () => _chooseStyle(settings.value!),
              icon: Icon(
                settings.value!.style == LineupStyle.field
                    ? Icons.sports_soccer
                    : Icons.view_agenda_outlined,
              ),
            ),
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
      body: switch ((athletes, lineup, settings, formation)) {
        (
          AsyncValue(value: final athletes?),
          AsyncValue(value: final lineup?),
          AsyncValue(value: final settings?),
          AsyncData(value: final formation),
        ) =>
          settings.style == LineupStyle.field && settings.fieldAvailable
              ? _field(athletes, lineup, formation)
              : _editor(context, athletes, lineup),
        (AsyncValue(hasError: true), _, _, _) ||
        (_, AsyncValue(hasError: true), _, _) ||
        (_, _, AsyncValue(hasError: true), _) ||
        (_, _, _, AsyncValue(hasError: true)) => Center(
          child: TextButton.icon(
            onPressed: () => ref
              ..invalidate(teamAthletesProvider(widget.teamId))
              ..invalidate(gameLineupProvider(widget.game.id!))
              ..invalidate(lineupSettingsProvider(widget.teamId))
              ..invalidate(gameFormationProvider(_key)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar. Tentar novamente'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  /// Escala de cada atleta, a partir da escalação salva (só na primeira
  /// carga).
  Map<String, _Spot> _initSpots(
    List<Athlete> athletes,
    List<LineupEntry> lineup,
  ) => _spots ??= {
    for (final athlete in athletes)
      athlete.id!: switch (lineup
          .where((entry) => entry.athleteId == athlete.id)
          .firstOrNull) {
        final entry? => entry.starter ? _Spot.starter : _Spot.sub,
        null => _Spot.out,
      },
  };

  /// Escalação no campo.
  Widget _field(
    List<Athlete> athletes,
    List<LineupEntry> lineup,
    String? savedFormation,
  ) {
    final spots = _initSpots(athletes, lineup);
    final formation = _formation ??= formationNamed(
      widget.game.modality,
      savedFormation,
    );
    final placed = _placed ??= () {
      final starters = [
        for (final athlete in athletes)
          if (spots[athlete.id] == _Spot.starter) athlete.id!,
      ];
      final placed = placeStarters(
        spots: formation.spots.length,
        starters: starters,
        slots: {for (final entry in lineup) entry.athleteId: ?entry.slot},
      );
      // Titulares que não couberam vão para a reserva.
      for (final id in starters) {
        if (!placed.containsValue(id)) spots[id] = _Spot.sub;
      }
      return placed;
    }();
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
    return TacticalLineup(
      pitch: pitchFor(widget.game.modality),
      formations: formationsFor(widget.game.modality),
      formation: formation,
      athletes: athletes,
      placed: placed,
      reserves: {
        for (final MapEntry(key: id, value: spot) in spots.entries)
          if (spot == _Spot.sub) id,
      },
      onFormation: (value) => setState(() => _formation = value),
      onPlace: _place,
      onRemove: _removeFromField,
      onToggleReserve: _toggleReserve,
    );
  }

  Widget _editor(
    BuildContext context,
    List<Athlete> athletes,
    List<LineupEntry> lineup,
  ) {
    final theme = Theme.of(context);
    final spots = _initSpots(athletes, lineup);
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
          AthleteAvatar(name: athlete.displayName, photoUrl: athlete.photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (athlete.jerseyNumber case final number?) '$number',
                    athlete.displayName,
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
