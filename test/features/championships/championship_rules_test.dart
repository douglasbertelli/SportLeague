import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/championships/domain/championship.dart';
import 'package:sport_league/features/championships/domain/championship_rules.dart';
import 'package:sport_league/features/teams/domain/team.dart';

Championship _champ(
  ChampionshipFormat format, {
  bool doubleRound = false,
  int? groups,
  int? qualifiers,
}) => Championship(
  ownerId: 'u1',
  name: 'Copa',
  modality: Modality.society,
  format: format,
  doubleRound: doubleRound,
  groupCount: groups,
  qualifiersPerGroup: qualifiers,
);

ChampionshipMatch _played(
  String home,
  String away,
  int h,
  int a, {
  MatchStage stage = MatchStage.league,
  int round = 1,
  int slot = 0,
  int? hp,
  int? ap,
}) => ChampionshipMatch(
  id: '$home-$away-$round',
  championshipId: 'c1',
  stage: stage,
  round: round,
  slot: slot,
  homeId: home,
  awayId: away,
  homeScore: h,
  awayScore: a,
  homePenalties: hp,
  awayPenalties: ap,
);

void main() {
  group('todos contra todos', () {
    test('cada par joga uma vez e ninguém joga duas vezes na rodada', () {
      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      final matches = roundRobin(ids);
      expect(matches.length, 15);
      expect(matches.map((m) => m.round).toSet().length, 5);
      final pairs = matches.map((m) => {m.homeId, m.awayId}).toList();
      for (final x in ids) {
        for (final y in ids) {
          if (x == y) continue;
          expect(
            pairs.where((p) => p.containsAll([x, y])).length,
            1,
            reason: '$x x $y',
          );
        }
      }
      for (var round = 1; round <= 5; round++) {
        final playing = [
          for (final m in matches.where((m) => m.round == round)) ...[
            m.homeId,
            m.awayId,
          ],
        ];
        expect(playing.toSet().length, playing.length);
      }
      // O mando fica equilibrado: ninguém joga em casa mais de 3 vezes.
      for (final id in ids) {
        final home = matches.where((m) => m.homeId == id).length;
        expect(home, inInclusiveRange(2, 3), reason: id);
      }
    });

    test('número ímpar: um time folga por rodada', () {
      final matches = roundRobin(['a', 'b', 'c', 'd', 'e']);
      expect(matches.length, 10);
      expect(matches.map((m) => m.round).toSet().length, 5);
      for (var round = 1; round <= 5; round++) {
        expect(matches.where((m) => m.round == round).length, 2);
      }
    });

    test('returno inverte o mando', () {
      final matches = roundRobin(['a', 'b', 'c', 'd'], doubleRound: true);
      expect(matches.length, 12);
      expect(matches.map((m) => m.round).toSet(), {1, 2, 3, 4, 5, 6});
      final first = matches.firstWhere((m) => m.round == 1);
      expect(
        matches.where(
          (m) =>
              m.round == 4 &&
              m.homeId == first.awayId &&
              m.awayId == first.homeId,
        ),
        hasLength(1),
      );
    });
  });

  test('chaveamento: primeira fase completa e as seguintes a definir', () {
    final matches = knockoutBracket(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
    expect(matches.length, 7);
    final quarters = matches.where((m) => m.round == 1).toList();
    expect(quarters.map((m) => (m.homeId, m.awayId)), [
      ('a', 'b'),
      ('c', 'd'),
      ('e', 'f'),
      ('g', 'h'),
    ]);
    expect(matches.where((m) => m.round == 2), hasLength(2));
    expect(matches.where((m) => m.round == 3), hasLength(1));
    expect(
      matches.where((m) => m.round > 1).every((m) => m.homeId == null),
      isTrue,
    );
    expect(knockoutRoundName(4), 'Quartas de final');
    expect(knockoutRoundName(1), 'Final');
  });

  test('o vencedor vai para o jogo seguinte, no lado certo', () {
    final next = ChampionshipMatch(
      id: 'semi',
      championshipId: 'c1',
      stage: MatchStage.knockout,
      round: 2,
      slot: 1,
    );
    final quarter = _played(
      'e',
      'f',
      1,
      1,
      stage: MatchStage.knockout,
      slot: 3,
      hp: 3,
      ap: 4,
    );
    // Empate decidido nos pênaltis.
    expect(quarter.winnerId, 'f');
    final slot = nextKnockoutSlot(quarter, [quarter, next]);
    expect(slot?.match.id, 'semi');
    expect(slot?.home, isFalse);
    // Na final não há próximo.
    expect(nextKnockoutSlot(next, [next]), isNull);
  });

  test('classificação: pontos, vitórias, saldo e gols', () {
    final table = standings(
      ['a', 'b', 'c', 'd'],
      [
        _played('a', 'b', 2, 0),
        _played('c', 'd', 1, 1),
        _played('a', 'c', 0, 1),
        _played('b', 'd', 3, 0),
      ],
    );
    // a e b: 3 pontos, 1 vitória e saldo +1; b fez mais gols (3 x 2).
    expect(table.map((r) => r.teamId), ['c', 'b', 'a', 'd']);
    final c = table.first;
    expect((c.points, c.played, c.wins, c.draws, c.losses), (4, 2, 1, 1, 0));
    expect((table[1].goalDifference, table[1].goalsFor), (1, 3));
    expect((table[2].goalDifference, table[2].goalsFor), (1, 2));
  });

  test('mata-mata a partir dos grupos', () {
    StandingRow row(String id) => StandingRow(id);
    final groups = [
      [row('a1'), row('a2'), row('a3')],
      [row('b1'), row('b2'), row('b3')],
    ];
    expect(knockoutFromGroups(groups, 2), ['a1', 'b2', 'b1', 'a2']);
    expect(knockoutFromGroups(groups, 1), ['a1', 'b1']);
  });

  test('grupos sorteados e jogos só dentro do grupo', () {
    final champ = _champ(ChampionshipFormat.groups, groups: 2, qualifiers: 2);
    final ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    final groups = drawGroups(ids, 2, Random(1));
    expect(groups.values.where((g) => g == 'A'), hasLength(4));
    final matches = planChampionship(champ, ids, groups: groups);
    expect(matches.length, 12);
    for (final m in matches) {
      expect(groups[m.homeId], m.groupLabel);
      expect(groups[m.awayId], m.groupLabel);
    }
  });

  test('quando dá para gerar a tabela', () {
    expect(cannotGenerate(_champ(ChampionshipFormat.league), 2), isNotNull);
    expect(cannotGenerate(_champ(ChampionshipFormat.league), 3), isNull);
    expect(cannotGenerate(_champ(ChampionshipFormat.knockout), 6), isNotNull);
    expect(cannotGenerate(_champ(ChampionshipFormat.knockout), 8), isNull);
    final groups = _champ(ChampionshipFormat.groups, groups: 2, qualifiers: 2);
    expect(cannotGenerate(groups, 5), contains('pelo menos 6'));
    expect(cannotGenerate(groups, 6), isNull);
  });
}
