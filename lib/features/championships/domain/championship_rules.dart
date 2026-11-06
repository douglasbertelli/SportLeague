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

/// Até 16 grupos.
const groupLabels = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
];

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
      final layout = GroupsLayout.of(championship, confirmed: teams);
      if (layout.error case final error?) return error;
      if (teams != layout.teams) {
        return 'Este campeonato é de ${layout.teams} times: confirme '
            'exatamente ${layout.teams} (agora são $teams).';
      }
      return null;
  }
}

/// Menor potência de 2 que cabe [n] (o tamanho do chaveamento).
int bracketSize(int n) {
  var size = 2;
  while (size < n) {
    size *= 2;
  }
  return size;
}

/// Como fica a fase de grupos + mata-mata: [teams] times em [groups] grupos
/// (o mais parelho possível), [qualifiers] classificados direto de cada um
/// e, quando eles não fecham o chaveamento, o jeito de completar ([fill]).
class GroupsLayout {
  const GroupsLayout({
    required this.teams,
    required this.groups,
    required this.qualifiers,
    this.fill,
  });

  /// A partir do máximo de times por grupo.
  factory GroupsLayout.fromMax({
    required int teams,
    required int maxPerGroup,
    required int qualifiers,
    KnockoutFill? fill,
  }) => GroupsLayout(
    teams: teams,
    groups: maxPerGroup < 1 ? 0 : (teams / maxPerGroup).ceil(),
    qualifiers: qualifiers,
    fill: fill,
  );

  /// O do campeonato. Os criados antes da quantidade de times usam os
  /// [confirmed].
  factory GroupsLayout.of(Championship championship, {int? confirmed}) =>
      GroupsLayout(
        teams: championship.teamCount ?? confirmed ?? 0,
        groups: championship.groupCount ?? 0,
        qualifiers: championship.qualifiersPerGroup ?? 1,
        fill: championship.knockoutFill,
      );

  static const minTeams = 4;
  static const maxTeams = 64;
  static const maxGroups = 16;

  final int teams;
  final int groups;
  final int qualifiers;
  final KnockoutFill? fill;

  /// Times de cada grupo, na ordem A, B, C…: os primeiros ficam com um a
  /// mais quando a divisão não é exata (como no sorteio).
  List<int> get sizes => groups <= 0
      ? const []
      : [
          for (var i = 0; i < groups; i++)
            teams ~/ groups + (i < teams % groups ? 1 : 0),
        ];

  int get smallestGroup => sizes.isEmpty ? 0 : sizes.reduce(min);

  /// Classificados direto (os [qualifiers] primeiros de cada grupo).
  int get direct => groups * qualifiers;

  /// Times no chaveamento (2, 4, 8, 16…).
  int get bracket => bracketSize(direct);

  /// Vagas que faltam para fechar o chaveamento.
  int get missing => bracket - direct;

  /// Dá para completar com os melhores da posição seguinte (um por grupo).
  bool get canUseBestPlaced => missing <= groups;

  /// Como completa, de fato: nulo quando fecha; folga quando não há
  /// melhores colocados que bastem.
  KnockoutFill? get effectiveFill => missing == 0
      ? null
      : fill == KnockoutFill.bestPlaced && canUseBestPlaced
      ? KnockoutFill.bestPlaced
      : KnockoutFill.byes;

  /// Por que o formato não vale; nulo se vale.
  String? get error {
    if (teams < minTeams || teams > maxTeams) {
      return 'O campeonato precisa ter de $minTeams a $maxTeams times.';
    }
    if (groups < 2) return 'Precisa de pelo menos 2 grupos.';
    if (groups > maxGroups) return 'Podem ser no máximo $maxGroups grupos.';
    if (smallestGroup < 2) return 'Cada grupo precisa de pelo menos 2 times.';
    if (qualifiers < 1 || qualifiers >= smallestGroup) {
      return 'Os classificados por grupo precisam ser menos que os times do '
          'menor grupo ($smallestGroup).';
    }
    return null;
  }

  /// "2 grupos de 4", "3 grupos: A com 4, B e C com 3".
  String get groupsText {
    final s = sizes;
    if (s.isEmpty) return '';
    if (s.toSet().length == 1) return '$groups grupos de ${s.first}';
    final big = s.first;
    final bigCount = s.where((n) => n == big).length;
    String labels(Iterable<String> l) {
      final list = l.toList();
      return list.length == 1
          ? list.single
          : '${list.take(list.length - 1).join(', ')} e ${list.last}';
    }

    return '$groups grupos: ${labels(groupLabels.take(bigCount))} com $big, '
        '${labels(groupLabels.skip(bigCount).take(groups - bigCount))} com '
        '${big - 1}';
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
/// primeira fase completa e as seguintes a definir. Nulo é folga: o outro
/// time do par não joga a primeira fase e já entra no jogo seguinte.
List<PlannedMatch> knockoutBracket(
  List<String?> bracket, {
  int firstRound = 1,
}) {
  assert(_isPowerOfTwo(bracket.length));
  final matches = <PlannedMatch>[];
  // Quem folga, por jogo da segunda fase: (mandante, visitante).
  final advanced = <int, (String?, String?)>{};
  for (var i = 0; i < bracket.length ~/ 2; i++) {
    final (home, away) = (bracket[i * 2], bracket[i * 2 + 1]);
    if (home != null && away != null) {
      matches.add(
        PlannedMatch(
          stage: MatchStage.knockout,
          round: firstRound,
          slot: i,
          homeId: home,
          awayId: away,
        ),
      );
    } else if (home ?? away case final team?) {
      final (h, a) = advanced[i ~/ 2] ?? (null, null);
      advanced[i ~/ 2] = i.isEven ? (team, a) : (h, team);
    }
  }
  var games = bracket.length ~/ 4;
  var round = firstRound + 1;
  while (games >= 1) {
    for (var slot = 0; slot < games; slot++) {
      final (home, away) = round == firstRound + 1
          ? advanced[slot] ?? (null, null)
          : (null, null);
      matches.add(
        PlannedMatch(
          stage: MatchStage.knockout,
          round: round,
          slot: slot,
          homeId: home,
          awayId: away,
        ),
      );
    }
    games ~/= 2;
    round++;
  }
  return matches;
}

/// Ordem das cabeças de chave no chaveamento de [size] (1 x 8, 4 x 5, 2 x 7,
/// 3 x 6…): a 1ª e a 2ª só se cruzam na final.
List<int> seedOrder(int size) {
  var order = [1, 2];
  while (order.length < size) {
    final next = order.length * 2;
    order = [
      for (final seed in order) ...[seed, next + 1 - seed],
    ];
  }
  return order;
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

/// Compara times de grupos diferentes (os de tamanhos diferentes também):
/// pontos por jogo, saldo por jogo, gols por jogo e vitórias.
int compareAcrossGroups(StandingRow a, StandingRow b) {
  double per(int value, StandingRow row) =>
      row.played == 0 ? 0 : value / row.played;
  for (final compare in [
    per(b.points, b).compareTo(per(a.points, a)),
    per(b.goalDifference, b).compareTo(per(a.goalDifference, a)),
    per(b.goalsFor, b).compareTo(per(a.goalsFor, a)),
    b.wins.compareTo(a.wins),
  ]) {
    if (compare != 0) return compare;
  }
  return 0;
}

/// Os melhores colocados da posição [position] (0 = 1º) entre os grupos,
/// do melhor para o pior.
List<StandingRow> bestAtPosition(
  List<List<StandingRow>> byGroup,
  int position,
) {
  final rows = [
    for (final group in byGroup)
      if (group.length > position) group[position],
  ];
  // Ordenação estável: no empate, vale a ordem dos grupos.
  return [
    for (final (_, row)
        in rows.indexed.toList()..sort((a, b) {
          final compare = compareAcrossGroups(a.$2, b.$2);
          return compare != 0 ? compare : a.$1.compareTo(b.$1);
        }))
      row,
  ];
}

/// O mata-mata a partir da classificação de cada grupo ([byGroup], na ordem
/// A, B, C…), já na ordem do chaveamento (nulo = folga).
///
/// Os classificados viram cabeças de chave: primeiro os 1º colocados (do
/// melhor para o pior), depois os 2º e assim por diante; com
/// [KnockoutFill.bestPlaced] entram por último os melhores da posição
/// seguinte. As melhores cabeças pegam as piores (e as folgas, que vão para
/// os melhores). Times do mesmo grupo não se enfrentam na primeira fase
/// quando dá para evitar.
List<String?> knockoutFromGroups(
  List<List<StandingRow>> byGroup,
  int qualifiers, {
  KnockoutFill? fill,
}) {
  final groupOf = {
    for (final (index, group) in byGroup.indexed)
      for (final row in group) row.teamId: index,
  };
  final seeds = <String>[
    for (var position = 0; position < qualifiers; position++)
      for (final row in bestAtPosition(byGroup, position)) row.teamId,
  ];
  final size = bracketSize(seeds.length);
  if (fill == KnockoutFill.bestPlaced) {
    final missing = size - seeds.length;
    seeds.addAll([
      for (final row in bestAtPosition(byGroup, qualifiers).take(missing))
        row.teamId,
    ]);
  }
  final bracket = <String?>[
    for (final seed in seedOrder(size))
      seed <= seeds.length ? seeds[seed - 1] : null,
  ];

  // Evita confronto do mesmo grupo na primeira fase: troca o adversário com
  // o de outro jogo quando a troca resolve os dois.
  bool clash(String? a, String? b) =>
      a != null && b != null && groupOf[a] == groupOf[b];
  for (var i = 0; i < bracket.length; i += 2) {
    if (!clash(bracket[i], bracket[i + 1])) continue;
    for (var j = 0; j < bracket.length; j += 2) {
      if (j == i || bracket[j + 1] == null) continue;
      if (!clash(bracket[i], bracket[j + 1]) &&
          !clash(bracket[j], bracket[i + 1])) {
        final away = bracket[i + 1];
        bracket[i + 1] = bracket[j + 1];
        bracket[j + 1] = away;
        break;
      }
    }
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

/// Nome da fase [round] do mata-mata pelos jogos que ela teria (as folgas
/// não têm jogo, mas contam).
String knockoutRoundNameOf(int round, Iterable<ChampionshipMatch> matches) {
  final last = matches
      .where((m) => m.stage == MatchStage.knockout)
      .map((m) => m.round)
      .fold(round, max);
  return knockoutRoundName(1 << (last - round));
}

/// Nome da fase do mata-mata pelo número de jogos nela.
String knockoutRoundName(int games) => switch (games) {
  1 => 'Final',
  2 => 'Semifinal',
  4 => 'Quartas de final',
  8 => 'Oitavas de final',
  _ => '${games * 2} avos de final',
};

/// "na semifinal", "nas quartas de final", "nos 32 avos de final" (ou, com
/// [to], "para a semifinal", "para as quartas de final"…).
String inKnockoutRound(int games, {bool to = false}) {
  final name = knockoutRoundName(games).toLowerCase();
  final (article, contracted) = switch (games) {
    1 || 2 => ('a', 'na'),
    4 || 8 => ('as', 'nas'),
    _ => ('os', 'nos'),
  };
  return to ? 'para $article $name' : '$contracted $name';
}
