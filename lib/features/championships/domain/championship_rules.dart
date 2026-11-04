import 'dart:math';

import 'championship.dart';

/// Jogo a criar (antes de ir para o banco).
class PlannedMatch {
  const PlannedMatch({
    required this.stage,
    required this.round,
    this.slot = 0,
    this.groupLabel,
    this.homeId,
    this.awayId,
  });

  final MatchStage stage;
  final int round;
  final int slot;
  final String? groupLabel;
  final String? homeId;
  final String? awayId;

  Map<String, dynamic> toMap(String championshipId) => {
    'championship_id': championshipId,
    'stage': stage.name,
    'round': round,
    'slot': slot,
    'group_label': groupLabel,
    'home_id': homeId,
    'away_id': awayId,
  };

  @override
  String toString() =>
      'PlannedMatch(${stage.name} r$round s$slot ${groupLabel ?? ''} '
      '$homeId x $awayId)';
}

const groupLabels = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

bool _isPowerOfTwo(int n) => n >= 2 && (n & (n - 1)) == 0;

/// Por que ainda não dá para gerar a tabela com [teams] times confirmados;
/// nulo se dá.
String? cannotGenerate(Championship championship, int teams) {
  switch (championship.format) {
    case ChampionshipFormat.league:
      return teams < 3 ? 'Confirme pelo menos 3 times.' : null;
    case ChampionshipFormat.knockout:
      if (_isPowerOfTwo(teams) && teams >= 4) return null;
      return 'O mata-mata precisa de 4, 8, 16 ou 32 times confirmados '
          '(agora são $teams).';
    case ChampionshipFormat.groups:
      final groups = championship.groupCount!;
      final qualifiers = championship.qualifiersPerGroup!;
      if (!_isPowerOfTwo(groups * qualifiers)) {
        return 'Com $groups grupos e $qualifiers classificados por grupo o '
            'mata-mata não fecha. Mude o formato.';
      }
      final needed = groups * max(qualifiers + 1, 2);
      return teams < needed
          ? 'Confirme pelo menos $needed times ($groups grupos com '
                '${needed ~/ groups} times cada).'
          : null;
  }
}

/// Todos contra todos (método do círculo): cada time joga uma vez com cada
/// outro por turno, alternando mando; com [doubleRound], o returno inverte o
/// mando. Com número ímpar de times, um folga em cada rodada.
List<PlannedMatch> roundRobin(
  List<String> ids, {
  bool doubleRound = false,
  MatchStage stage = MatchStage.league,
  String? groupLabel,
}) {
  final teams = <String?>[...ids];
  if (teams.length.isOdd) teams.add(null); // folga
  final count = teams.length;
  final rounds = count - 1;
  final firstLeg = <PlannedMatch>[];
  for (var round = 0; round < rounds; round++) {
    var slot = 0;
    for (var i = 0; i < count ~/ 2; i++) {
      final a = teams[i];
      final b = teams[count - 1 - i];
      if (a == null || b == null) continue;
      // Alterna o mando do time fixo e dos pares a cada rodada.
      final swap = i == 0 ? round.isOdd : i.isOdd;
      firstLeg.add(
        PlannedMatch(
          stage: stage,
          round: round + 1,
          slot: slot++,
          groupLabel: groupLabel,
          homeId: swap ? b : a,
          awayId: swap ? a : b,
        ),
      );
    }
    // Gira todos menos o primeiro.
    teams.insert(1, teams.removeLast());
  }
  if (!doubleRound) return firstLeg;
  return [
    ...firstLeg,
    for (final match in firstLeg)
      PlannedMatch(
        stage: stage,
        round: match.round + rounds,
        slot: match.slot,
        groupLabel: groupLabel,
        homeId: match.awayId,
        awayId: match.homeId,
      ),
  ];
}

/// Chaveamento com os times na ordem de [bracket] (1º x 2º, 3º x 4º…): a
/// primeira fase completa e as seguintes a definir.
List<PlannedMatch> knockoutBracket(List<String> bracket, {int firstRound = 1}) {
  assert(_isPowerOfTwo(bracket.length));
  final matches = <PlannedMatch>[
    for (var i = 0; i < bracket.length ~/ 2; i++)
      PlannedMatch(
        stage: MatchStage.knockout,
        round: firstRound,
        slot: i,
        homeId: bracket[i * 2],
        awayId: bracket[i * 2 + 1],
      ),
  ];
  var games = bracket.length ~/ 4;
  var round = firstRound + 1;
  while (games >= 1) {
    for (var slot = 0; slot < games; slot++) {
      matches.add(
        PlannedMatch(stage: MatchStage.knockout, round: round, slot: slot),
      );
    }
    games ~/= 2;
    round++;
  }
  return matches;
}

/// Sorteia os times em [groupCount] grupos, o mais parelho possível.
Map<String, String> drawGroups(
  List<String> ids,
  int groupCount, [
  Random? random,
]) {
  final shuffled = [...ids]..shuffle(random);
  return {
    for (final (index, id) in shuffled.indexed)
      id: groupLabels[index % groupCount],
  };
}

/// Os jogos de todo o campeonato, a partir dos times confirmados ([ids]) e,
/// no formato com grupos, dos grupos sorteados ([groups]). No mata-mata, a
/// ordem do chaveamento é sorteada; nos grupos, o mata-mata vem depois.
List<PlannedMatch> planChampionship(
  Championship championship,
  List<String> ids, {
  Map<String, String> groups = const {},
  Random? random,
}) => switch (championship.format) {
  ChampionshipFormat.league => roundRobin(
    [...ids]..shuffle(random),
    doubleRound: championship.doubleRound,
  ),
  ChampionshipFormat.knockout => knockoutBracket([...ids]..shuffle(random)),
  ChampionshipFormat.groups => [
    for (final label in groupLabels.take(championship.groupCount!))
      ...roundRobin(
        [
          for (final id in ids)
            if (groups[id] == label) id,
        ],
        doubleRound: championship.doubleRound,
        stage: MatchStage.group,
        groupLabel: label,
      ),
  ],
};

/// Uma linha da classificação.
class StandingRow {
  StandingRow(this.teamId);

  final String teamId;
  int played = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;

  int get points => wins * 3 + draws;
  int get goalDifference => goalsFor - goalsAgainst;
}

/// Classificação dos [ids] pelos jogos com placar: pontos (3 por vitória, 1
/// por empate), vitórias, saldo de gols, gols marcados e, por fim, o nome
/// ([names]).
List<StandingRow> standings(
  List<String> ids,
  Iterable<ChampionshipMatch> matches, {
  Map<String, String> names = const {},
}) {
  final rows = {for (final id in ids) id: StandingRow(id)};
  for (final match in matches) {
    if (!match.hasScore || !match.hasTeams) continue;
    final home = rows[match.homeId];
    final away = rows[match.awayId];
    if (home == null || away == null) continue;
    final (h, a) = (match.homeScore!, match.awayScore!);
    home
      ..played += 1
      ..goalsFor += h
      ..goalsAgainst += a;
    away
      ..played += 1
      ..goalsFor += a
      ..goalsAgainst += h;
    if (h > a) {
      home.wins++;
      away.losses++;
    } else if (a > h) {
      away.wins++;
      home.losses++;
    } else {
      home.draws++;
      away.draws++;
    }
  }
  return rows.values.toList()..sort((a, b) {
    for (final compare in [
      b.points.compareTo(a.points),
      b.wins.compareTo(a.wins),
      b.goalDifference.compareTo(a.goalDifference),
      b.goalsFor.compareTo(a.goalsFor),
    ]) {
      if (compare != 0) return compare;
    }
    return (names[a.teamId] ?? a.teamId).compareTo(names[b.teamId] ?? b.teamId);
  });
}

/// O mata-mata a partir da classificação de cada grupo ([byGroup], na ordem
/// A, B, C…): com 1 classificado, A x B, C x D…; com 2, o 1º de um grupo
/// pega o 2º do grupo vizinho (1A x 2B, 1B x 2A…).
List<String> knockoutFromGroups(
  List<List<StandingRow>> byGroup,
  int qualifiers,
) {
  if (qualifiers == 1) {
    return [for (final group in byGroup) group.first.teamId];
  }
  final bracket = <String>[];
  for (var i = 0; i < byGroup.length; i += 2) {
    final a = byGroup[i];
    final b = byGroup[i + 1];
    bracket.addAll([a[0].teamId, b[1].teamId, b[0].teamId, a[1].teamId]);
  }
  return bracket;
}

/// Onde o vencedor de [match] entra: o jogo da fase seguinte e se como
/// mandante (posição par) ou visitante. Nulo na final.
({ChampionshipMatch match, bool home})? nextKnockoutSlot(
  ChampionshipMatch match,
  Iterable<ChampionshipMatch> matches,
) {
  if (match.stage != MatchStage.knockout) return null;
  final next = matches
      .where(
        (m) =>
            m.stage == MatchStage.knockout &&
            m.round == match.round + 1 &&
            m.slot == match.slot ~/ 2,
      )
      .firstOrNull;
  return next == null ? null : (match: next, home: match.slot.isEven);
}

/// Nome da fase do mata-mata pelo número de jogos nela.
String knockoutRoundName(int games) => switch (games) {
  1 => 'Final',
  2 => 'Semifinal',
  4 => 'Quartas de final',
  8 => 'Oitavas de final',
  _ => '${games * 2} avos de final',
};
