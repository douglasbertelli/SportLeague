import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/athletes/domain/athlete.dart';
import 'package:sport_league/features/championships/domain/championship.dart';
import 'package:sport_league/features/championships/domain/championship_rules.dart';
import 'package:sport_league/features/games/data/lineup_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/domain/game_event.dart';
import 'package:sport_league/features/games/domain/match_clock.dart';
import 'package:sport_league/features/sports/domain/sport_rules.dart';
import 'package:sport_league/features/teams/domain/team.dart';

/// As regras do futebol precisam ser exatamente as de antes do SportRules:
/// estes valores estavam escritos direto no código.
void main() {
  const rules = footballRules;

  group('modalidades', () {
    test('as cinco de antes são do futebol; o vôlei tem as dele', () {
      for (final modality in _footballModalities) {
        expect(modality.sport, Sport.football, reason: modality.name);
      }
      expect(rules.modalities, _footballModalities);
      expect(Modality.of(Sport.volleyball), [
        Modality.volleyballIndoor,
        Modality.volleyballBeach,
      ]);
      expect(Modality.of(Sport.basketball), isEmpty);
    });
  });

  group('tempos', () {
    test('duração de cada tempo por modalidade', () {
      const expected = {
        Modality.futsal: 20,
        Modality.society: 25,
        Modality.field: 45,
        Modality.beach: 15,
        Modality.challenge: 10,
      };
      for (final MapEntry(key: modality, value: minutes) in expected.entries) {
        expect(
          rules.periodMinutesFor(modality),
          minutes,
          reason: modality.name,
        );
        expect(MatchClock.defaultPeriodMinutes(modality), minutes);
      }
      expect(rules.periodMinutesFor(null), 10);
      expect(MatchClock.defaultPeriodMinutes(null), 10);
    });

    test('dois tempos com intervalo e acréscimo, e relógio', () {
      expect(rules.periods.count, 2);
      expect(rules.periods.names, [
        MatchPhase.first.label,
        MatchPhase.second.label,
      ]);
      expect(rules.periods.intervalName, MatchPhase.interval.label);
      expect(rules.periods.hasAddedTime, isTrue);
      expect(rules.hasClock, isTrue);
    });
  });

  test('titulares por modalidade', () {
    const expected = {
      Modality.futsal: 5,
      Modality.society: 7,
      Modality.field: 11,
      Modality.beach: 5,
      Modality.challenge: 5,
    };
    for (final MapEntry(key: modality, value: starters) in expected.entries) {
      expect(rules.startersFor(modality), starters, reason: modality.name);
      expect(startersFor(modality), starters);
    }
    expect(rules.startersFor(null), 5);
    expect(startersFor(null), 5);
  });

  test('posições e pé dominante', () {
    expect(rules.positions, footballPositions);
    expect(rules.positions, [
      'Goleiro',
      'Zagueiro',
      'Lateral',
      'Volante',
      'Meia',
      'Atacante',
      'Centroavante',
    ]);
    expect(rules.usesDominantFoot, isTrue);
    expect(rules.supportsFieldLineup, isTrue);
  });

  test('placar: gols, empate e pênaltis no mata-mata', () {
    expect(rules.allowsDraw, isTrue);
    expect(rules.knockoutTiebreak, KnockoutTiebreak.penalties);
    expect(rules.scoreUnit.count(1), '1 gol');
    expect(rules.scoreUnit.count(3), '3 gols');
  });

  test('súmula: as colunas de game_player_stats', () {
    expect(rules.stats.map((stat) => stat.key), [
      'goals',
      'assists',
      'yellow_cards',
      'red_card',
    ]);
    expect(rules.stat('yellow_cards')?.max, 2);
    expect(rules.stat('red_card')?.kind, StatKind.flag);
    expect(rules.stat('assists')?.shortLabel, 'Assist.');
    expect(rules.stat('points'), isNull);
    expect(rules.eventKinds, GameEventKind.values);
  });

  test('rankings: Artilharia pelos gols e Garçons pelas assistências', () {
    expect(
      [for (final ranking in rules.rankings) (ranking.title, ranking.statKey)],
      [('Artilharia', 'goals'), ('Garçons', 'assists')],
    );
    for (final ranking in rules.rankings) {
      expect(rules.stat(ranking.statKey), isNotNull);
    }
  });

  group('classificação', () {
    test('3 por vitória, 1 por empate, 0 por derrota', () {
      expect(rules.standings.pointsFor(wins: 2, draws: 1, losses: 4), 7);
      expect(rules.standings.tiebreakers, [
        StandingsTiebreaker.points,
        StandingsTiebreaker.wins,
        StandingsTiebreaker.scoreDifference,
        StandingsTiebreaker.scoreFor,
      ]);
    });

    test('é a mesma conta da classificação do campeonato', () {
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
      final table = standings(
        ['a', 'b', 'c'],
        [match('a', 'b', 2, 0), match('b', 'c', 1, 1), match('c', 'a', 3, 1)],
      );
      for (final row in table) {
        expect(
          row.points,
          rules.standings.pointsFor(
            wins: row.wins,
            draws: row.draws,
            losses: row.losses,
          ),
          reason: row.teamId,
        );
      }
    });
  });

  group('esporte de time, jogo e campeonato', () {
    test('listas de escolha só com as modalidades dos esportes liberados', () {
      // Futebol e vôlei (liberado no build +8), nessa ordem.
      expect(availableModalities, Modality.values);
    });

    test('futebol e vôlei liberados; o basquete ainda sem regras', () {
      expect(supportedSports, [Sport.football, Sport.volleyball]);
      expect(rulesFor(Sport.football), same(footballRules));
      expect(rulesFor(Sport.volleyball), same(volleyballRules));
      expect(() => rulesFor(Sport.basketball), throwsUnsupportedError);
      expect(rulesForModality(null), same(footballRules));
    });

    test('time, jogo e campeonato de futebol usam as regras do futebol', () {
      const team = Team(ownerId: 'o', name: 'Time');
      expect(team.rules, same(footballRules));

      final game = Game(
        teamId: 't',
        opponent: 'Rival',
        scheduledAt: DateTime(2026, 11, 26, 20),
        modality: Modality.futsal,
      );
      expect(game.sport, Sport.football);
      expect(game.rules, same(footballRules));

      final noModality = Game(
        teamId: 't',
        opponent: 'Rival',
        scheduledAt: DateTime(2026, 11, 26, 20),
      );
      expect(noModality.rules, same(footballRules));

      const championship = Championship(
        ownerId: 'o',
        name: 'Copa',
        modality: Modality.field,
        format: ChampionshipFormat.league,
      );
      expect(championship.sport, Sport.football);
      expect(championship.rules, same(footballRules));
    });
  });
}

/// As modalidades de antes do vôlei, todas do futebol.
const _footballModalities = [
  Modality.futsal,
  Modality.society,
  Modality.field,
  Modality.beach,
  Modality.challenge,
];
