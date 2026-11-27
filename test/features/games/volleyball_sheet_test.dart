import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/championships/domain/championship_stats.dart';
import 'package:sport_league/features/games/domain/player_stats.dart';
import 'package:sport_league/features/games/presentation/game_sheet_page.dart';
import 'package:sport_league/features/profile/presentation/my_numbers_section.dart';
import 'package:sport_league/features/sports/domain/sport_rules.dart';

/// Etapa 6 da Fase 2: súmula e rankings do vôlei.
void main() {
  const base = {'game_id': 'g', 'team_id': 't', 'athlete_id': 'a'};

  group('linha da súmula', () {
    test('lê pontos, aces e bloqueios de stats', () {
      final row = PlayerGameStats.fromMap({
        ...base,
        'stats': {'points': 12, 'aces': 2, 'blocks': 3},
      });
      expect(row.value('points'), 12);
      expect(row.value('aces'), 2);
      expect(row.value('blocks'), 3);
      expect(row.value('goals'), 0);
      expect(row.extra, {'points': 12, 'aces': 2, 'blocks': 3});
    });

    test('grava só as chaves do esporte do jogo', () {
      final row = const PlayerGameStats(
        gameId: 'g',
        teamId: 't',
        athleteId: 'a',
      ).withValue('points', 8).withValue('blocks', 1);
      final keys = [for (final stat in volleyballRules.stats) stat.key];
      expect(row.toMap(statKeys: keys)['stats'], {
        'points': 8,
        'aces': 0,
        'blocks': 1,
      });
      // O futebol continua gravando as quatro colunas.
      expect(
        const PlayerGameStats(
          gameId: 'g',
          teamId: 't',
          athleteId: 'a',
          goals: 2,
        ).toMap()['stats'],
        {'goals': 2, 'assists': 0, 'yellow_cards': 0, 'red_card': 0},
      );
    });

    test('resumo da súmula do vôlei', () {
      final row = PlayerGameStats.fromMap({
        ...base,
        'stats': {'points': 12, 'aces': 1, 'blocks': 0},
      });
      expect(statsLine(row, volleyballRules), '12 pontos · 1 ace');
    });
  });

  test('totais do atleta com as estatísticas do vôlei', () {
    final totals = AthleteTotals.fromMap({
      'athlete_id': 'a',
      'name': 'Ana',
      'games': 4,
      'goals': 0,
      'stats': {'points': 50, 'aces': 6, 'blocks': 9},
    });
    expect(totals.value('points'), 50);
    expect(totals.value('blocks'), 9);
    expect(totals.value('goals'), 0);
  });

  testWidgets('quadro de números do vôlei', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerTotalsGrid(
            totals: AthleteTotals(
              athleteId: 'a',
              name: 'Ana',
              games: 4,
              bestPlayer: 1,
              extra: {'points': 50, 'aces': 6, 'blocks': 9},
            ),
            rules: volleyballRules,
          ),
        ),
      ),
    );
    for (final label in ['Jogos', 'Pontos', 'Aces', 'Bloq.', 'Craque']) {
      expect(find.text(label), findsOne, reason: label);
    }
    expect(find.text('50'), findsOne);
    expect(find.text('Gols'), findsNothing);
  });

  test('ranking do campeonato pela estatística do esporte', () {
    final stats = ChampionshipStats.fromMap({
      'players': [
        {
          'name': 'Ana',
          'team_name': 'A',
          'stats': {'points': 20, 'aces': 1},
        },
        {
          'name': 'Bia',
          'team_name': 'B',
          'stats': {'points': 35, 'aces': 0},
        },
        {
          'name': 'Cris',
          'team_name': 'C',
          'stats': {'points': 0},
        },
      ],
    });
    expect(stats.ranking('points').map((p) => p.name), ['Bia', 'Ana']);
    expect(stats.ranking('aces').map((p) => p.name), ['Ana']);
    // O futebol continua pelos gols.
    final football = ChampionshipStats.fromMap({
      'players': [
        {'name': 'Ana', 'team_name': 'A', 'goals': 2},
        {'name': 'Bia', 'team_name': 'B', 'goals': 5},
      ],
    });
    expect(football.ranking('goals').map((p) => p.name), ['Bia', 'Ana']);
    expect(football.ranking('goals'), football.scorers);
  });
}
