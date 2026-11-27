import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/championships/domain/championship.dart';
import 'package:sport_league/features/championships/domain/championship_rules.dart';
import 'package:sport_league/features/sports/domain/sport_rules.dart';
import 'package:sport_league/features/teams/domain/team.dart';

/// Etapa 5 da Fase 2: campeonato do vôlei.
void main() {
  /// Jogo da liga com os [sets] (mandante, visitante); o placar são os sets
  /// vencidos, como o banco grava.
  ChampionshipMatch match(
    String home,
    String away,
    List<(int, int)> sets, {
    int round = 1,
  }) {
    final h = sets.where((s) => s.$1 > s.$2).length;
    final a = sets.length - h;
    return ChampionshipMatch(
      id: '$home-$away-$round',
      championshipId: 'c',
      stage: MatchStage.league,
      round: round,
      homeId: home,
      awayId: away,
      homeScore: h,
      awayScore: a,
      setScores: sets,
    );
  }

  test('modelo: melhor de e sets', () {
    final championship = Championship.fromMap({
      'id': 'c',
      'owner_id': 'o',
      'name': 'Copa',
      'modality': 'volleyball_indoor',
      'format': 'league',
      'status': 'draft',
      'best_of': 5,
    });
    expect(championship.bestOf, 5);
    expect(championship.rules, same(volleyballRules));
    expect(championship.toMap()['best_of'], 5);
    final m = ChampionshipMatch.fromMap({
      'id': 'm',
      'championship_id': 'c',
      'stage': 'league',
      'round': 1,
      'home_id': 'a',
      'away_id': 'b',
      'home_score': 3,
      'away_score': 1,
      'set_scores': [
        [25, 20],
        [23, 25],
        [25, 18],
        [25, 22],
      ],
    });
    expect(m.setScores, [(25, 20), (23, 25), (25, 18), (25, 22)]);
    expect(m.homeSetPoints, 98);
    expect(m.awaySetPoints, 85);
    expect(m.winnerId, 'a');
  });

  group('classificação CBV/FIVB', () {
    test('3 pela vitória, 2 e 1 no tie-break', () {
      final table = standings(
        ['a', 'b', 'c'],
        [
          // a vence b por 3x0: 3 para a.
          match('a', 'b', [(25, 20), (25, 20), (25, 20)]),
          // b vence c por 3x2: 2 para b, 1 para c.
          match('b', 'c', [(25, 20), (20, 25), (25, 20), (20, 25), (15, 10)]),
        ],
        rules: volleyballStandings,
      );
      final points = {for (final row in table) row.teamId: row.points};
      expect(points, {'a': 3, 'b': 2, 'c': 1});
      final b = table.firstWhere((row) => row.teamId == 'b');
      expect((b.wins, b.closeWins, b.losses, b.closeLosses), (1, 1, 1, 0));
      // Saldo de sets: b ganhou 3 e perdeu 5 (0x3 e 3x2).
      expect((b.goalsFor, b.goalsAgainst), (3, 5));
      expect(table.map((row) => row.teamId), ['a', 'b', 'c']);
    });

    test(
      'saldo de pontos desempata pontos, vitórias e saldo de sets iguais',
      () {
        // a e b: uma vitória 3x0 cada, contra times diferentes; a com mais
        // pontos de saldo.
        final table = standings(
          ['a', 'b', 'x', 'y'],
          [
            match('a', 'x', [(25, 10), (25, 10), (25, 10)]),
            match('b', 'y', [(25, 23), (25, 23), (25, 23)]),
          ],
          rules: volleyballStandings,
        );
        final top = table.take(2).toList();
        expect(top.map((row) => row.teamId), ['a', 'b']);
        expect(top.first.pointDifference, 45);
        expect(top.last.pointDifference, 6);
      },
    );

    test('o futebol não muda: vitória por um gol vale 3', () {
      final table = standings(
        ['a', 'b'],
        [
          ChampionshipMatch(
            id: 'm',
            championshipId: 'c',
            stage: MatchStage.league,
            round: 1,
            homeId: 'a',
            awayId: 'b',
            homeScore: 2,
            awayScore: 1,
          ),
        ],
      );
      expect(table.first.points, 3);
      expect(table.first.pointDifference, 0);
    });
  });

  test('a regra de suspensão não vale no vôlei (sem cartão na súmula)', () {
    expect(volleyballRules.stat('yellow_cards'), isNull);
    expect(footballRules.stat('yellow_cards'), isNotNull);
    expect(Modality.volleyballBeach.sport, Sport.volleyball);
  });
}
