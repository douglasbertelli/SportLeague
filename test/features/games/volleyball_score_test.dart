import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/presentation/sets_sheet.dart';
import 'package:sport_league/features/sports/domain/sport_rules.dart';
import 'package:sport_league/features/teams/domain/team.dart';

/// Etapa 4 da Fase 2: placar em sets do vôlei.
void main() {
  Game game({
    String teamId = 'host',
    Modality modality = Modality.volleyballIndoor,
    int? bestOf = 5,
    Object? sets,
  }) => Game.fromMap({
    'id': 'g',
    'team_id': teamId,
    'opponent': 'Rival',
    'opponent_team_id': 'rival',
    'scheduled_at': '2026-11-26T20:00:00Z',
    'modality': modality.key,
    'best_of': bestOf,
    'set_scores': sets,
    'team_score': 3,
    'opponent_score': 1,
  });

  group('modelo', () {
    test('lê o melhor de e os sets do banco', () {
      final g = game(
        sets: [
          [25, 20],
          [23, 25],
          [25, 18],
          [25, 22],
        ],
      );
      expect(g.bestOf, 5);
      expect(g.setScores, [(25, 20), (23, 25), (25, 18), (25, 22)]);
      expect(g.rules.sets, isNotNull);
    });

    test('na visão do adversário, os sets invertem', () {
      final g = game(
        sets: [
          [25, 20],
          [23, 25],
        ],
      );
      expect(g.setScoresFor('host'), [(25, 20), (23, 25)]);
      expect(g.setScoresFor('rival'), [(20, 25), (25, 23)]);
      expect(g.setsLabelFor('host'), '25-20, 23-25');
      expect(g.setsLabelFor('rival'), '20-25, 25-23');
    });

    test('sem sets (futebol ou vôlei ainda sem placar)', () {
      expect(game(sets: null).setScores, isNull);
      expect(game(sets: null).setsLabelFor('host'), isNull);
      expect(game(sets: []).setsLabelFor('host'), isNull);
      // Formato inesperado não quebra.
      expect(
        parseSetScores([
          [25, 'x'],
        ]),
        isNull,
      );
      expect(parseSetScores('25-20'), isNull);
      expect(setScoresToJson([(25, 20), (21, 25)]), [
        [25, 20],
        [21, 25],
      ]);
    });

    test('o formulário grava o melhor de', () {
      expect(game().toMap()['best_of'], 5);
      expect(game().toMap().containsKey('set_scores'), isFalse);
    });
  });

  group('partida em andamento', () {
    final sets = volleyballRules.sets!;

    test('progress aceita a partida sem vencedor', () {
      expect(
        sets.progress(
          [(25, 20), (23, 25)],
          modality: Modality.volleyballIndoor,
          bestOf: 5,
        ),
        (a: 1, b: 1),
      );
      expect(
        sets.progress(const [], modality: Modality.volleyballIndoor, bestOf: 5),
        (a: 0, b: 0),
      );
      // Mas não um set que não terminou.
      expect(
        sets.progress(
          [(25, 24)],
          modality: Modality.volleyballIndoor,
          bestOf: 5,
        ),
        isNull,
      );
    });

    test('isOver só com alguém fechando os sets', () {
      expect(sets.isOver((a: 2, b: 1), 5), isFalse);
      expect(sets.isOver((a: 3, b: 1), 5), isTrue);
      expect(sets.isOver((a: 1, b: 2), 3), isTrue);
    });
  });

  group('tela dos sets', () {
    Future<List<(int, int)>?> open(
      WidgetTester tester,
      Game g, {
      required bool complete,
      required List<(String, String)> typed,
    }) async {
      List<(int, int)>? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showSetsSheet(
                  context,
                  game: g,
                  myTeam: 'Nós',
                  opponent: 'Rival',
                  requireComplete: complete,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      for (var i = 1; i < typed.length; i++) {
        await tester.tap(find.text('Adicionar set'));
        await tester.pumpAndSettle();
      }
      final fields = find.byType(TextField);
      for (final (index, (mine, theirs)) in typed.indexed) {
        await tester.enterText(fields.at(index * 2), mine);
        await tester.enterText(fields.at(index * 2 + 1), theirs);
      }
      await tester.tap(find.text('Salvar placar'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('placar ao vivo salva set a set', (tester) async {
      final result = await open(
        tester,
        game(sets: null),
        complete: false,
        typed: [('25', '20')],
      );
      expect(result, [(25, 20)]);
    });

    testWidgets('placar final exige a partida terminada', (tester) async {
      final result = await open(
        tester,
        game(sets: null, bestOf: 3),
        complete: true,
        typed: [('25', '20')],
      );
      expect(result, isNull);
      expect(find.textContaining('A partida ainda não terminou'), findsOne);
    });

    testWidgets('set que não terminou não salva', (tester) async {
      final result = await open(
        tester,
        game(sets: null),
        complete: false,
        typed: [('25', '24')],
      );
      expect(result, isNull);
      expect(find.textContaining('Algum set não terminou'), findsOne);
    });

    testWidgets('melhor de 3 completo salva', (tester) async {
      final result = await open(
        tester,
        game(sets: null, bestOf: 3),
        complete: true,
        typed: [('25', '20'), ('20', '25'), ('15', '13')],
      );
      expect(result, [(25, 20), (20, 25), (15, 13)]);
    });
  });
}
