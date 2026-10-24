import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/theme/app_theme.dart';
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
