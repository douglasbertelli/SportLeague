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
    const groups = Championship(
      ownerId: 'u1',
      name: 'Copa',
      modality: Modality.society,
      format: ChampionshipFormat.groups,
      groupCount: 2,
      qualifiersPerGroup: 2,
      teamCount: 6,
      groupSize: 3,
    );
    expect(cannotGenerate(groups, 5), contains('exatamente 6'));
    expect(cannotGenerate(groups, 6), isNull);
  });

  group('grupos flexíveis', () {
    test('divide o mais parelho possível e descreve', () {
      final even = GroupsLayout.fromMax(
        teams: 8,
        maxPerGroup: 4,
        qualifiers: 2,
      );
      expect(even.groups, 2);
      expect(even.sizes, [4, 4]);
      expect(even.groupsText, '2 grupos de 4');
      expect(even.missing, 0);
      expect(even.effectiveFill, isNull);
      expect(even.error, isNull);

      final uneven = GroupsLayout.fromMax(
        teams: 10,
        maxPerGroup: 4,
        qualifiers: 2,
      );
      expect(uneven.sizes, [4, 3, 3]);
      expect(uneven.groupsText, '3 grupos: A com 4, B e C com 3');
      expect(uneven.direct, 6);
      expect(uneven.bracket, 8);
      expect(uneven.missing, 2);
    });

    test('completa com os melhores colocados ou com folgas', () {
      final best = GroupsLayout.fromMax(
        teams: 12,
        maxPerGroup: 4,
        qualifiers: 2,
        fill: KnockoutFill.bestPlaced,
      );
      expect(best.effectiveFill, KnockoutFill.bestPlaced);
      // 5 grupos com 1 classificado: 5 no chaveamento de 8, faltam 3 (há 5
      // segundos colocados).
      final five = GroupsLayout.fromMax(
        teams: 15,
        maxPerGroup: 3,
        qualifiers: 1,
        fill: KnockoutFill.bestPlaced,
      );
      expect(five.missing, 3);
      expect(five.canUseBestPlaced, isTrue);
      // 3 grupos com 3 classificados: 9 no de 16, faltam 7 e só há 3
      // quartos colocados: só dá com folgas.
      final nine = GroupsLayout.fromMax(
        teams: 15,
        maxPerGroup: 5,
        qualifiers: 3,
        fill: KnockoutFill.bestPlaced,
      );
      expect(nine.canUseBestPlaced, isFalse);
      expect(nine.effectiveFill, KnockoutFill.byes);
    });

    test('formatos inválidos', () {
      expect(
        GroupsLayout.fromMax(teams: 8, maxPerGroup: 8, qualifiers: 2).error,
        contains('2 grupos'),
      );
      expect(
        GroupsLayout.fromMax(teams: 8, maxPerGroup: 4, qualifiers: 4).error,
        contains('menor grupo'),
      );
      expect(
        GroupsLayout.fromMax(teams: 3, maxPerGroup: 2, qualifiers: 1).error,
        contains('de 4 a 64'),
      );
    });

    test('cabeças de chave: 1ª e 2ª só na final', () {
      expect(seedOrder(4), [1, 4, 2, 3]);
      expect(seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    });

    StandingRow row(String id, {int wins = 0, int played = 2}) =>
        StandingRow(id)
          ..played = played
          ..wins = wins
          ..losses = played - wins;

    test('melhores colocados entram e ninguém do mesmo grupo se cruza', () {
      // 3 grupos, 2 classificados + os 2 melhores 3º = 8.
      final byGroup = [
        [row('a1', wins: 2), row('a2', wins: 1), row('a3', wins: 1)],
        [row('b1', wins: 2), row('b2', wins: 1), row('b3')],
        [row('c1', wins: 1), row('c2', wins: 1), row('c3', wins: 1)],
      ];
      final bracket = knockoutFromGroups(
        byGroup,
        2,
        fill: KnockoutFill.bestPlaced,
      );
      expect(bracket, hasLength(8));
      expect(bracket.whereType<String>().toSet(), {
        'a1', 'a2', 'b1', 'b2', 'c1', 'c2', 'a3', 'c3', // b3 fica de fora
      });
      String group(String? id) => id![0];
      for (var i = 0; i < 8; i += 2) {
        expect(group(bracket[i]), isNot(group(bracket[i + 1])));
      }
    });

    test('folga: os melhores passam direto para a fase seguinte', () {
      // 3 grupos com 2 classificados = 6 no chaveamento de 8: 2 folgas.
      final byGroup = [
        [row('a1', wins: 2), row('a2', wins: 1), row('a3')],
        [row('b1', wins: 1), row('b2', wins: 1), row('b3')],
        [row('c1', wins: 2), row('c2'), row('c3')],
      ];
      final bracket = knockoutFromGroups(byGroup, 2, fill: KnockoutFill.byes);
      expect(bracket.where((id) => id == null), hasLength(2));
      final matches = knockoutBracket(bracket, firstRound: 4);
      final first = matches.where((m) => m.round == 4).toList();
      final second = matches.where((m) => m.round == 5).toList();
      expect(first, hasLength(2));
      expect(second, hasLength(2));
      // Os dois melhores 1º (a1 e c1) folgam e já estão na semifinal.
      final waiting = {
        for (final m in second) ...[m.homeId, m.awayId],
      }.whereType<String>();
      expect(waiting.toSet(), {'a1', 'c1'});
      expect(matches.where((m) => m.round == 6), hasLength(1));
    });

    test('nome da fase conta as folgas', () {
      ChampionshipMatch ko(int round, int slot) => ChampionshipMatch(
        id: '$round-$slot',
        championshipId: 'c1',
        stage: MatchStage.knockout,
        round: round,
        slot: slot,
      );
      // Quartas com só 1 jogo (3 folgas), semifinal e final.
      final matches = [ko(2, 0), ko(3, 0), ko(3, 1), ko(4, 0)];
      expect(knockoutRoundNameOf(2, matches), 'Quartas de final');
      expect(knockoutRoundNameOf(3, matches), 'Semifinal');
      expect(knockoutRoundNameOf(4, matches), 'Final');
    });
  });
}
