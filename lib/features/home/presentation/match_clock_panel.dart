import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/whistle_player.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/data/game_repository.dart';
import '../../games/domain/game.dart';
import '../../games/domain/match_clock.dart';

/// Relógio da partida no card do jogo em andamento: cronômetro do tempo
/// atual, com aviso quando acaba o tempo regulamentar. Quem marcou o jogo
/// inicia, pausa e encerra cada tempo; o adversário acompanha (e o app busca
/// o relógio de novo de tempos em tempos para ele ver as pausas).
class MatchClockPanel extends ConsumerStatefulWidget {
  const MatchClockPanel({
    super.key,
    required this.game,
    required this.viewerTeamId,
    this.clock,
  });

  final Game game;
  final String viewerTeamId;

  /// Hora atual (testes).
  final DateTime Function()? clock;

  @override
  ConsumerState<MatchClockPanel> createState() => _MatchClockPanelState();
}

class _MatchClockPanelState extends ConsumerState<MatchClockPanel> {
  Timer? _tick;
  Timer? _refresh;
  bool _saving = false;
  late bool _wasOvertime = _overtime;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  bool get _isHost => widget.game.isHostedBy(widget.viewerTeamId);

  bool get _overtime => widget.game.clock?.overtimeAt(_now()) ?? false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    if (!_isHost) {
      _refresh = Timer.periodic(
        const Duration(seconds: 20),
        (_) => ref.invalidate(teamGamesProvider(widget.viewerTeamId)),
      );
    }
  }

  @override
  void didUpdateWidget(MatchClockPanel old) {
    super.didUpdateWidget(old);
    final from = old.game.clock?.phase;
    final to = widget.game.clock?.phase;
    // Outro tempo ou o relógio zerado: o aviso vale de novo.
    if (from != to) {
      _wasOvertime = _overtime;
      // O adversário ouve o apito quando o relógio dele atualiza (quem
      // marcou já ouviu ao tocar no botão).
      if (!_isHost && to != null) _whistleFor(to);
    }
  }

  /// Apito de cada mudança de tempo.
  void _whistleFor(MatchPhase phase) {
    ref.read(playWhistleProvider)(switch (phase) {
      MatchPhase.first || MatchPhase.second => Whistle.start,
      MatchPhase.interval => Whistle.halfTime,
      MatchPhase.finished => Whistle.fullTime,
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted || !(widget.game.clock?.running ?? false)) return;
    setState(() {});
    final overtime = _overtime;
    if (overtime && !_wasOvertime) {
      HapticFeedback.heavyImpact();
      final phase = widget.game.clock!.phase;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Acabou o tempo do ${phase.label}. O relógio segue no acréscimo.',
          ),
        ),
      );
    }
    _wasOvertime = overtime;
  }

  Future<void> _run(ClockAction action, {int? periodMinutes}) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(gameRepositoryProvider)
          .clock(widget.game.id!, action, periodMinutes: periodMinutes);
      // Apito na hora, mesmo que o card troque de jogo em seguida.
      switch (action) {
        case ClockAction.start || ClockAction.startSecond:
          _whistleFor(MatchPhase.first);
        case ClockAction.endHalf:
          _whistleFor(MatchPhase.interval);
        case ClockAction.finish:
          _whistleFor(MatchPhase.finished);
        case ClockAction.pause || ClockAction.resume || ClockAction.reset:
          break;
      }
      ref.invalidate(teamGamesProvider(widget.viewerTeamId));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _start() async {
    final minutes = await showAppSheet<int>(
      context,
      builder: (_) => _PeriodSheet(
        initial: MatchClock.defaultPeriodMinutes(widget.game.modality),
      ),
    );
    if (minutes != null) await _run(ClockAction.start, periodMinutes: minutes);
  }

  Future<void> _confirmThen(
    ClockAction action, {
    required String title,
    required String message,
    required String label,
  }) async {
    if (await confirmAction(
      context,
      title: title,
      message: message,
      confirmLabel: label,
    )) {
      await _run(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final clock = widget.game.clock;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    if (clock == null) {
      return _isHost
          ? Center(
              child: FilledButton.tonalIcon(
                onPressed: _saving ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar 1º tempo'),
              ),
            )
          : Center(child: Text('Aguardando o início da partida', style: muted));
    }

    final now = _now();
    final overtime = clock.overtimeAt(now);
    final ticking =
        clock.phase == MatchPhase.first || clock.phase == MatchPhase.second;
    final minutes = clock.periodMinutes;
    final enabled = !_saving;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                [
                  // No fim de jogo, o título do card já diz; aqui fica o
                  // tempo final do 2º tempo.
                  if (clock.phase == MatchPhase.finished)
                    '2º tempo encerrado'
                  else
                    clock.phase.label,
                  if (ticking && minutes != null) '$minutes min',
                  if (ticking && !clock.running) 'pausado',
                ].join(' · '),
                style: muted,
              ),
            ),
            if (overtime)
              Text(
                'Acréscimo',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (_isHost)
              PopupMenuButton<void>(
                tooltip: 'Mais opções do relógio',
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    onTap: () => _confirmThen(
                      ClockAction.reset,
                      title: 'Zerar o relógio?',
                      message:
                          'O relógio volta para antes do 1º tempo. O placar '
                          'não muda.',
                      label: 'Zerar',
                    ),
                    child: const Text('Zerar relógio'),
                  ),
                ],
              ),
          ],
        ),
        if (ticking || clock.phase == MatchPhase.finished)
          Text(
            formatClock(clock.elapsedAt(now)),
            semanticsLabel:
                '${clock.elapsedAt(now).inMinutes} minutos de ${clock.phase.label}',
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: overtime ? colors.error : null,
            ),
          ),
        if (_isHost) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (ticking)
                clock.running
                    ? OutlinedButton.icon(
                        onPressed: enabled
                            ? () => _run(ClockAction.pause)
                            : null,
                        icon: const Icon(Icons.pause),
                        label: const Text('Pausar'),
                      )
                    : OutlinedButton.icon(
                        onPressed: enabled
                            ? () => _run(ClockAction.resume)
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Continuar'),
                      ),
              if (clock.phase == MatchPhase.first)
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () => _confirmThen(
                          ClockAction.endHalf,
                          title: 'Encerrar o 1º tempo?',
                          message: 'O relógio para e começa o intervalo.',
                          label: 'Encerrar 1º tempo',
                        )
                      : null,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Encerrar 1º tempo'),
                ),
              if (clock.phase == MatchPhase.interval)
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () => _run(ClockAction.startSecond)
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar 2º tempo'),
                ),
              if (clock.phase == MatchPhase.second)
                FilledButton.tonalIcon(
                  onPressed: enabled
                      ? () => _confirmThen(
                          ClockAction.finish,
                          title: 'Encerrar a partida?',
                          message:
                              'O relógio para. O placar ainda pode ser '
                              'corrigido.',
                          label: 'Encerrar jogo',
                        )
                      : null,
                  icon: const Icon(Icons.sports_score),
                  label: const Text('Encerrar jogo'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Duração de cada tempo, ao iniciar a partida.
class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.initial});

  final int initial;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late int _minutes = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSheet(
      title: 'Iniciar a partida',
      message: 'Duração de cada tempo. O app avisa quando ela acabar.',
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            tooltip: 'Menos 1 minuto',
            onPressed: _minutes > 1 ? () => setState(() => _minutes--) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 120,
            child: Text(
              '$_minutes min',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
          ),
          IconButton.outlined(
            tooltip: 'Mais 1 minuto',
            onPressed: _minutes < 60 ? () => setState(() => _minutes++) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_minutes),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar 1º tempo'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}
