import 'dart:async';

import 'package:flutter/material.dart';

/// Quanto falta para a partida, discreto: "6d 01h 28min" ou, no último dia,
/// "01h 29min 50s". Atualiza sozinho a cada segundo.
class GameCountdown extends StatefulWidget {
  const GameCountdown({
    super.key,
    required this.startsAt,
    this.clock,
    this.onStarted,
  });

  final DateTime startsAt;

  /// Chamado uma vez quando a contagem chega a zero com a tela aberta (não
  /// se o jogo já tinha começado ao abrir).
  final VoidCallback? onStarted;

  /// Hora atual (testes); o padrão é o relógio do aparelho.
  final DateTime Function()? clock;

  @override
  State<GameCountdown> createState() => _GameCountdownState();
}

class _GameCountdownState extends State<GameCountdown> {
  late final Timer _timer;
  late bool _running = widget.startsAt.isAfter(_now());

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_running && !widget.startsAt.isAfter(_now())) {
        _running = false;
        widget.onStarted?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final left = widget.startsAt.difference(_now());
    String two(int value) => value.toString().padLeft(2, '0');

    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;
    final (text, label) = left.isNegative
        ? ('Começou', 'A partida começou')
        : (
            days > 0
                ? '${days}d ${two(hours)}h ${two(minutes)}min'
                // No último dia, os segundos mostram que está chegando.
                : '${two(hours)}h ${two(minutes)}min '
                      '${two(left.inSeconds % 60)}s',
            'Faltam ${days > 0 ? '$days ${days == 1 ? 'dia' : 'dias'}, ' : ''}'
                '$hours horas e $minutes minutos',
          );

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(text, style: style),
        ],
      ),
    );
  }
}
