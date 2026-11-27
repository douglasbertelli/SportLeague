import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/sports/presentation/sport_picker.dart';
import 'package:sport_league/features/teams/domain/team.dart';

void main() {
  testWidgets('um card por esporte liberado, com ícone; o toque escolhe', (
    tester,
  ) async {
    Sport? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SportPicker(
            selected: Sport.football,
            onChanged: (sport) => picked = sport,
          ),
        ),
      ),
    );
    expect(find.text('Futebol'), findsOneWidget);
    expect(find.text('Vôlei'), findsOneWidget);
    expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
    expect(find.byIcon(Icons.sports_volleyball), findsOneWidget);
    expect(find.text('Basquete'), findsNothing);

    await tester.tap(find.text('Vôlei'));
    expect(picked, Sport.volleyball);
  });
}
