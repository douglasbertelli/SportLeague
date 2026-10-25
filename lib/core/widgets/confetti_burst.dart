import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

/// Explosão de confetes por cima da tela inteira, que some sozinha. Não
/// aparece com "remover animações" ligado no aparelho.
void showConfettiBurst(BuildContext context) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ConfettiBurst(onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst> {
  final _controller = ConfettiController(
    duration: const Duration(milliseconds: 800),
  );
  late final Timer _done;

  @override
  void initState() {
    super.initState();
    _controller.play();
    // Tempo para os confetes caírem até o fim da tela.
    _done = Timer(const Duration(seconds: 5), widget.onDone);
  }

  @override
  void dispose() {
    _done.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.3),
        child: ConfettiWidget(
          confettiController: _controller,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: 30,
          emissionFrequency: 0.08,
          maxBlastForce: 40,
          minBlastForce: 15,
          gravity: 0.25,
          colors: [
            colors.primary,
            colors.tertiary,
            colors.secondary,
            Colors.amber,
            Colors.white,
          ],
        ),
      ),
    );
  }
}
