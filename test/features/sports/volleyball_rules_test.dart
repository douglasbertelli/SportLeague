import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/sports/domain/sport_rules.dart';
import 'package:sport_league/features/teams/domain/team.dart';

/// Regras do vôlei (Etapa 1 da Fase 2): existem, mas ainda não estão
/// liberadas.
void main() {
  const rules = volleyballRules;
  final sets = volleyballRules.sets!;

  test('liberado (build +8)', () {
    expect(supportedSports, contains(Sport.volleyball));
    expect(availableModalities, contains(Modality.volleyballIndoor));
    expect(rulesFor(Sport.volleyball), same(volleyballRules));
    expect(rulesForModality(Modality.volleyballBeach), same(volleyballRules));
  });

  test('modalidades: quadra e praia, com a chave do banco', () {
    expect(rules.modalities, [
      Modality.volleyballIndoor,
      Modality.volleyballBeach,
    ]);
    expect(Modality.volleyballIndoor.label, 'Quadra');
    expect(Modality.volleyballBeach.label, 'Praia');
    expect(Modality.volleyballIndoor.key, 'volleyball_indoor');
    expect(Modality.volleyballBeach.key, 'volleyball_beach');
    // Nas listas que misturam esportes, o esporte vem junto.
    expect(Modality.volleyballBeach.fullLabel, 'Vôlei · Praia');
    expect(Modality.beach.fullLabel, 'Futebol · Areia');
    // As do futebol continuam com o nome de sempre.
    expect(Modality.futsal.key, 'futsal');
    for (final modality in Modality.values) {
      expect(Modality.fromName(modality.key), modality);
    }
  });

  test('sem relógio, sem empate, sem pênaltis e sem escalação no campo', () {
    expect(rules.hasClock, isFalse);
    expect(rules.allowsDraw, isFalse);
    expect(rules.knockoutTiebreak, KnockoutTiebreak.none);
    expect(rules.supportsFieldLineup, isFalse);
    expect(rules.usesDominantFoot, isFalse);
    expect(rules.eventKinds, isEmpty);
    expect(rules.periods.names.first, '1º set');
  });

  test('titulares e posições por modalidade', () {
    expect(rules.startersFor(Modality.volleyballIndoor), 6);
    expect(rules.startersFor(Modality.volleyballBeach), 2);
    expect(rules.positionsFor(Modality.volleyballIndoor), [
      'Levantador',
      'Oposto',
      'Ponteiro',
      'Central',
      'Líbero',
    ]);
    expect(rules.positionsFor(Modality.volleyballBeach), [
      'Bloqueador',
      'Defensor',
    ]);
    // No futebol, sem diferença por modalidade.
    expect(
      footballRules.positionsFor(Modality.society),
      footballRules.positions,
    );
  });

  test('súmula: pontos, aces e bloqueios', () {
    expect(rules.stats.map((s) => s.key), ['points', 'aces', 'blocks']);
    expect(rules.scoringStatKey, 'points');
    expect(rules.stat('points')!.unit.count(12), '12 pontos');
    expect(rules.stat('blocks')!.unit.count(1), '1 bloqueio');
    expect(rules.rankings.map((r) => r.statKey), ['points', 'aces', 'blocks']);
    for (final ranking in rules.rankings) {
      expect(rules.stat(ranking.statKey), isNotNull);
    }
  });

  group('sets', () {
    test('melhor de 3 ou de 5; quadra sugere 5, praia 3', () {
      expect(sets.bestOfOptions, [3, 5]);
      expect(sets.defaultBestOf[Modality.volleyballIndoor], 5);
      expect(sets.defaultBestOf[Modality.volleyballBeach], 3);
      expect(sets.setsToWin(3), 2);
      expect(sets.setsToWin(5), 3);
    });

    test('25 na quadra, 21 na praia e tie-break de 15', () {
      expect(sets.targetFor(Modality.volleyballIndoor, 1, 5), 25);
      expect(sets.targetFor(Modality.volleyballIndoor, 4, 5), 25);
      expect(sets.targetFor(Modality.volleyballIndoor, 5, 5), 15);
      expect(sets.targetFor(Modality.volleyballBeach, 1, 3), 21);
      expect(sets.targetFor(Modality.volleyballBeach, 3, 3), 15);
      expect(sets.targetFor(Modality.volleyballIndoor, 3, 3), 15);
    });

    test('set terminado: chegou ao alvo com 2 de diferença', () {
      expect(sets.isFinishedSet(25, 20, 25), isTrue);
      expect(sets.isFinishedSet(23, 25, 25), isTrue);
      expect(sets.isFinishedSet(26, 24, 25), isTrue);
      expect(sets.isFinishedSet(31, 29, 25), isTrue);
      expect(sets.isFinishedSet(15, 13, 15), isTrue);
      // Não terminou ou não vale.
      expect(sets.isFinishedSet(25, 24, 25), isFalse);
      expect(sets.isFinishedSet(24, 20, 25), isFalse);
      expect(sets.isFinishedSet(27, 24, 25), isFalse);
      expect(sets.isFinishedSet(25, 25, 25), isFalse);
      expect(sets.isFinishedSet(-1, 25, 25), isFalse);
    });

    test('partida: sets vencidos de cada lado', () {
      expect(
        sets.matchResult(
          [(25, 20), (23, 25), (25, 18), (25, 22)],
          modality: Modality.volleyballIndoor,
          bestOf: 5,
        ),
        (a: 3, b: 1),
      );
      expect(
        sets.matchResult(
          [(21, 19), (18, 21), (13, 15)],
          modality: Modality.volleyballBeach,
          bestOf: 3,
        ),
        (a: 1, b: 2),
      );
    });

    test('partida que não vale', () {
      ({int a, int b})? result(List<(int, int)> s, {int bestOf = 5}) => sets
          .matchResult(s, modality: Modality.volleyballIndoor, bestOf: bestOf);
      // Sem vencedor ainda.
      expect(result([(25, 20), (25, 20)]), isNull);
      // Set depois de alguém já ter vencido.
      expect(result([(25, 20), (25, 20), (25, 20), (25, 20)]), isNull);
      // Set que não terminou.
      expect(result([(25, 20), (25, 24), (25, 20), (25, 20)]), isNull);
      // Tie-break jogado como set normal: o alvo do 5º set é 15, e 25x20
      // passa do alvo sem a diferença exata de 2.
      expect(
        result([(25, 20), (20, 25), (25, 20), (20, 25), (25, 20)]),
        isNull,
      );
      // Já 25x23 no tie-break vale: foi para a vantagem e fechou com 2.
      expect(result([(25, 20), (20, 25), (25, 20), (20, 25), (25, 23)]), (
        a: 3,
        b: 2,
      ));
      expect(result([(25, 20), (20, 25), (25, 20), (20, 25), (15, 12)]), (
        a: 3,
        b: 2,
      ));
      // Melhor de 4 não existe.
      expect(result([(25, 20), (25, 20)], bestOf: 4), isNull);
    });

    test('apertado é a partida decidida no tie-break', () {
      expect(sets.isClose((a: 3, b: 2), 5), isTrue);
      expect(sets.isClose((a: 1, b: 3), 5), isFalse);
      expect(sets.isClose((a: 2, b: 1), 3), isTrue);
      expect(sets.isClose((a: 0, b: 2), 3), isFalse);
    });

    test('o futebol não tem sets', () {
      expect(footballRules.sets, isNull);
    });
  });

  group('classificação CBV/FIVB', () {
    const standings = volleyballStandings;

    test('3 pela vitória, 2 e 1 no tie-break, 0 pela derrota', () {
      expect(standings.pointsFor(wins: 1, draws: 0, losses: 0), 3);
      expect(
        standings.pointsFor(wins: 1, draws: 0, losses: 0, closeWins: 1),
        2,
      );
      expect(
        standings.pointsFor(wins: 0, draws: 0, losses: 1, closeLosses: 1),
        1,
      );
      expect(standings.pointsFor(wins: 0, draws: 0, losses: 1), 0);
      // 4 vitórias (1 no tie-break) e 3 derrotas (2 no tie-break).
      expect(
        standings.pointsFor(
          wins: 4,
          draws: 0,
          losses: 3,
          closeWins: 1,
          closeLosses: 2,
        ),
        3 * 3 + 2 + 2 * 1,
      );
    });

    test('desempate: vitórias, saldo de sets e saldo de pontos', () {
      expect(standings.tiebreakers, [
        StandingsTiebreaker.points,
        StandingsTiebreaker.wins,
        StandingsTiebreaker.scoreDifference,
        StandingsTiebreaker.pointDifference,
      ]);
    });

    test('o futebol não muda: apertado vale como as outras', () {
      expect(footballStandings.closeWin, footballStandings.win);
      expect(footballStandings.closeLoss, footballStandings.loss);
      expect(
        footballStandings.pointsFor(
          wins: 2,
          draws: 1,
          losses: 1,
          closeWins: 1,
          closeLosses: 1,
        ),
        7,
      );
    });
  });
}
