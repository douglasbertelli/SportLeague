import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/theme/app_theme.dart';
import 'package:sport_league/core/widgets/confetti_burst.dart';
import 'package:sport_league/features/home/presentation/game_countdown.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  final startsAt = DateTime(2026, 10, 31, 15);

  testWidgets('mais de um dia: dias, horas e minutos', (tester) async {
    await _pump(
      tester,
      GameCountdown(
        startsAt: startsAt,
        clock: () => DateTime(2026, 10, 29, 9, 47, 30),
      ),
    );
    // Os segundos só aparecem no último dia.
    expect(find.text('2d 05h 12min'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Faltam 2 dias, 5 horas e 12 minutos'),
      findsOneWidget,
    );
  });

  testWidgets('no último dia mostra os segundos e atualiza sozinho', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 31, 13, 30, 10);
    await _pump(tester, GameCountdown(startsAt: startsAt, clock: () => now));
    expect(find.text('01h 29min 50s'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('01h 29min 49s'), findsOneWidget);
  });

  testWidgets('avisa uma vez quando chega a zero', (tester) async {
    var now = DateTime(2026, 10, 31, 14, 59, 58);
    var started = 0;
    await _pump(
      tester,
      GameCountdown(
        startsAt: startsAt,
        clock: () => now,
        onStarted: () => started++,
      ),
    );
    for (var i = 0; i < 4; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(started, 1);
    expect(find.text('Começou'), findsOneWidget);
  });

  testWidgets('já começado ao abrir: não avisa', (tester) async {
    var started = 0;
    await _pump(
      tester,
      GameCountdown(
        startsAt: startsAt,
        clock: () => DateTime(2026, 10, 31, 15, 5),
        onStarted: () => started++,
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(started, 0);
  });

  testWidgets('confetes cobrem a tela e somem sozinhos', (tester) async {
    await _pump(tester, const SizedBox());
    showConfettiBurst(tester.element(find.byType(SizedBox)));
    await tester.pump();
    expect(find.byType(ConfettiWidget), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(ConfettiWidget), findsNothing);
  });

  testWidgets('sem confetes com animações desligadas', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    showConfettiBurst(tester.element(find.byType(SizedBox)));
    await tester.pump();
    expect(find.byType(ConfettiWidget), findsNothing);
  });

  testWidgets('depois do horário: começou', (tester) async {
    await _pump(
      tester,
      GameCountdown(
        startsAt: startsAt,
        clock: () => DateTime(2026, 10, 31, 15, 5),
      ),
    );
    expect(find.text('Começou'), findsOneWidget);
    expect(find.bySemanticsLabel('A partida começou'), findsOneWidget);
  });
}
