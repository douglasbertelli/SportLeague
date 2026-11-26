import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/championships/domain/championship.dart';
import 'package:sport_league/features/championships/domain/championship_rules.dart';
import 'package:sport_league/features/games/domain/match_clock.dart';
import 'package:sport_league/features/games/domain/player_stats.dart';
import 'package:sport_league/features/games/presentation/game_sheet_page.dart';
import 'package:sport_league/features/sports/domain/sport_rules.dart';

/// Etapa 2: as telas leem as regras do esporte. Os textos do futebol têm que
/// sair iguais aos de antes.
void main() {
  const row = PlayerGameStats(
    gameId: 'g',
    teamId: 't',
    athleteId: 'a',
    athleteName: 'Fulano',
    goals: 2,
    assists: 1,
    yellowCards: 1,
    redCard: true,
  );

  group('súmula pelas regras', () {
    test('value lê cada coluna e withValue grava', () {
      expect(row.value('goals'), 2);
      expect(row.value('assists'), 1);
      expect(row.value('yellow_cards'), 1);
      expect(row.value('red_card'), 1);
      expect(row.value('points'), 0);

      final edited = row
          .withValue('goals', 3)
          .withValue('assists', 0)
          .withValue('yellow_cards', 2)
          .withValue('red_card', 0);
      expect(
        (edited.goals, edited.assists, edited.yellowCards, edited.redCard),
        (3, 0, 2, false),
      );
      expect(row.withValue('points', 5).goals, 2);
    });

    test('resumo igual ao de antes', () {
      expect(statsLine(row), '2 gols · 1 assistência · 1 amarelo · vermelho');
      expect(
        statsLine(
          row.copyWith(goals: 1, assists: 2, yellowCards: 2, redCard: false),
        ),
        '1 gol · 2 assistências · 2 amarelos',
      );
      expect(
        statsLine(
          row.copyWith(goals: 0, assists: 0, yellowCards: 0, redCard: false),
        ),
        '',
      );
    });

    test('totais lêem cada coluna (vermelhos somados)', () {
      const totals = AthleteTotals(
        athleteId: 'a',
        name: 'Fulano',
        goals: 7,
        assists: 4,
        yellowCards: 3,
        redCards: 2,
      );
      expect(
        [for (final stat in footballRules.stats) totals.value(stat.key)],
        [7, 4, 3, 2],
      );
    });

    test('quadros de totais com os rótulos de antes', () {
      expect(
        [
          for (final stat in footballRules.stats)
            (stat.totalsLabel, stat.totalsTooltip, stat.emphasis),
        ],
        [
          ('Gols', null, StatEmphasis.primary),
          ('Assist.', 'Assistências', StatEmphasis.none),
          ('Amarelos', null, StatEmphasis.none),
          ('Vermelhos', null, StatEmphasis.error),
        ],
      );
    });
  });

  test('artilheiros como antes: "Fulano (2)", de quem fez mais', () {
    final stats = [
      row.copyWith(goals: 1),
      const PlayerGameStats(
        gameId: 'g',
        teamId: 't',
        athleteId: 'b',
        athleteName: 'Ciclano',
        goals: 3,
      ),
      const PlayerGameStats(gameId: 'g', teamId: 't', athleteId: 'c'),
    ];
    expect(scorerNames(stats, footballRules.scoringStatKey), [
      'Ciclano (3)',
      'Fulano',
    ]);
  });

  test('rankings com as unidades e a mensagem de antes', () {
    expect(
      [
        for (final ranking in footballRules.rankings)
          (ranking.unit, ranking.emptyMessage),
      ],
      [('gols', 'Nenhum gol lançado nas súmulas ainda.'), ('assist.', null)],
    );
  });

  test('fases do relógio com os nomes de antes', () {
    for (final phase in MatchPhase.values) {
      expect(phase.labelIn(footballRules.periods), phase.label);
    }
  });

  test('rótulos de gols pró e contra', () {
    expect(footballRules.scoreUnit.title, 'Gols');
  });

  group('classificação pelas regras', () {
    const ids = ['a', 'b', 'x', 'y', 'z'];

    /// Só as linhas de a e b, na ordem da classificação.
    List<StandingRow> only(List<StandingRow> table) => [
      for (final row in table)
        if (row.teamId == 'a' || row.teamId == 'b') row,
    ];

    ChampionshipMatch match(String home, String away, int h, int a) =>
        ChampionshipMatch(
          id: '$home-$away',
          championshipId: 'c',
          stage: MatchStage.league,
          round: 1,
          homeId: home,
          awayId: away,
          homeScore: h,
          awayScore: a,
        );

    test('outra pontuação muda a ordem', () {
      // a: 1 vitória e 2 derrotas; b: 3 empates.
      final matches = [
        match('a', 'x', 1, 0),
        match('a', 'y', 0, 1),
        match('a', 'z', 0, 1),
        match('b', 'x', 0, 0),
        match('b', 'y', 0, 0),
        match('b', 'z', 0, 0),
      ];
      final football = only(standings(ids, matches));
      expect(football.map((row) => (row.teamId, row.points)), [
        ('a', 3),
        ('b', 3),
      ]);

      const twoForWin = StandingsRules(
        win: 2,
        draw: 1,
        loss: 0,
        tiebreakers: [StandingsTiebreaker.points],
      );
      final other = only(standings(ids, matches, rules: twoForWin));
      expect(other.map((row) => (row.teamId, row.points)), [
        ('b', 3),
        ('a', 2),
      ]);
    });

    test('a ordem de desempate vem das regras', () {
      // Mesmos pontos; a tem mais gols marcados, b tem mais vitórias.
      final matches = [
        match('a', 'x', 5, 5),
        match('a', 'y', 5, 5),
        match('a', 'z', 5, 5),
        match('b', 'x', 1, 0),
        match('b', 'y', 0, 1),
        match('b', 'z', 0, 0),
      ];
      expect(only(standings(ids, matches)).first.teamId, 'b');

      const goalsFirst = StandingsRules(
        win: 2,
        draw: 1,
        loss: 0,
        tiebreakers: [StandingsTiebreaker.points, StandingsTiebreaker.scoreFor],
      );
      expect(
        only(standings(ids, matches, rules: goalsFirst)).first.teamId,
        'a',
      );
    });
  });
}
