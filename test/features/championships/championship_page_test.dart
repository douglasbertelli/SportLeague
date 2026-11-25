import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sport_league/core/media/picked_image.dart';
import 'package:sport_league/core/media/square_crop_page.dart';
import 'package:sport_league/core/supabase/supabase_providers.dart';
import 'package:sport_league/features/championships/data/championship_repository.dart';
import 'package:sport_league/features/championships/domain/championship.dart';
import 'package:sport_league/features/championships/domain/championship_stats.dart';
import 'package:sport_league/features/championships/domain/championship_rules.dart';
import 'package:sport_league/features/championships/presentation/championship_page.dart';
import 'package:sport_league/features/championships/presentation/share_championship.dart';
import 'package:sport_league/features/games/presentation/share_result.dart';
import 'package:sport_league/features/invites/data/invite_repository.dart'
    show shareTextProvider;
import 'package:sport_league/features/teams/domain/team.dart';

/// Campeonato em memória, com as mesmas regras do banco que a tela usa.
class FakeChampionshipRepository implements ChampionshipRepository {
  FakeChampionshipRepository(this.championship, this.teams);

  Championship championship;
  final List<ChampionshipTeam> teams;
  final matches = <ChampionshipMatch>[];
  final responses = <(String, bool)>[];
  var totals = <ChampionshipPlayerTotal>[];
  final guestLogos = <String, PickedImage?>{};
  var deleted = false;
  var _next = 0;

  @override
  Future<void> setGuestLogo(String guestTeamId, PickedImage? image) async {
    guestLogos[guestTeamId] = image;
    final i = teams.indexWhere((t) => t.guestTeamId == guestTeamId);
    final t = teams[i];
    teams[i] = ChampionshipTeam(
      id: t.id,
      championshipId: t.championshipId,
      guestTeamId: t.guestTeamId,
      name: t.name,
      status: t.status,
      logoUrl: image == null ? null : 'https://logo/$guestTeamId.png',
    );
  }

  @override
  Future<void> delete(String id) async => deleted = true;

  @override
  Future<String> setPublic(
    String id, {
    required bool enabled,
    bool newLink = false,
  }) async {
    final slug = championship.publicSlug == null || newLink
        ? 'cod${_next++}'
        : championship.publicSlug!;
    championship = championship.copyWith(
      publicEnabled: enabled,
      publicSlug: slug,
    );
    return slug;
  }

  @override
  Future<List<ChampionshipPlayerTotal>> fetchPlayerTotals(String id) async =>
      totals;

  var stats = const ChampionshipStats();
  var requests = <ChampionshipRequest>[];
  final answers = <(String, bool)>[];

  @override
  Future<ChampionshipStats> fetchStats(String id) async => stats;

  @override
  Future<List<ChampionshipRequest>> fetchRequests(String id) async => requests;

  @override
  Future<void> answerRequest(String requestId, {required bool accept}) async {
    answers.add((requestId, accept));
    requests = [
      for (final request in requests)
        if (request.id != requestId) request,
    ];
  }

  @override
  Future<String> setSignup(
    String id, {
    required bool enabled,
    bool newCode = false,
  }) async {
    championship = championship.copyWith(
      signupEnabled: enabled,
      signupCode: championship.signupCode ?? 'abcd1234',
    );
    return championship.signupCode!;
  }

  @override
  Future<Championship> fetch(String id) async => championship;

  @override
  Future<List<ChampionshipTeam>> fetchTeams(String id) async => [...teams];

  @override
  Future<List<ChampionshipMatch>> fetchMatches(String id) async => [...matches];

  @override
  Future<List<Championship>> fetchMine() async => [championship];

  @override
  Future<void> respond(String entryId, {required bool accept}) async =>
      responses.add((entryId, accept));

  @override
  Future<void> removeTeam(String entryId) async =>
      teams.removeWhere((t) => t.id == entryId);

  @override
  Future<void> start(
    Championship championship,
    List<PlannedMatch> planned, {
    Map<String, String> groups = const {},
  }) async {
    for (final (index, team) in [...teams].indexed) {
      teams[index] = ChampionshipTeam(
        id: team.id,
        championshipId: team.championshipId,
        teamId: team.teamId,
        guestTeamId: team.guestTeamId,
        name: team.name,
        status: team.status,
        groupLabel: groups[team.id],
      );
    }
    await addMatches(championship.id!, planned);
    this.championship = championship.copyWith(
      status: ChampionshipStatus.running,
    );
  }

  @override
  Future<void> addMatches(String id, List<PlannedMatch> planned) async {
    for (final p in planned) {
      matches.add(
        ChampionshipMatch(
          id: 'm${_next++}',
          championshipId: id,
          stage: p.stage,
          round: p.round,
          slot: p.slot,
          groupLabel: p.groupLabel,
          homeId: p.homeId,
          awayId: p.awayId,
        ),
      );
    }
  }

  ChampionshipMatch _copy(
    ChampionshipMatch m, {
    String? homeId,
    String? awayId,
    bool setSides = false,
    int? home,
    int? away,
    int? homePen,
    int? awayPen,
    bool setScore = false,
  }) => ChampionshipMatch(
    id: m.id,
    championshipId: m.championshipId,
    stage: m.stage,
    round: m.round,
    slot: m.slot,
    groupLabel: m.groupLabel,
    homeId: setSides ? homeId : m.homeId,
    awayId: setSides ? awayId : m.awayId,
    scheduledAt: m.scheduledAt,
    homeScore: setScore ? home : m.homeScore,
    awayScore: setScore ? away : m.awayScore,
    homePenalties: setScore ? homePen : m.homePenalties,
    awayPenalties: setScore ? awayPen : m.awayPenalties,
  );

  @override
  Future<void> setScore(
    String matchId, {
    required int? home,
    required int? away,
    int? homePenalties,
    int? awayPenalties,
  }) async {
    final i = matches.indexWhere((m) => m.id == matchId);
    matches[i] = _copy(
      matches[i],
      home: home,
      away: away,
      homePen: homePenalties,
      awayPen: awayPenalties,
      setScore: true,
    );
  }

  @override
  Future<void> setSide(
    String matchId, {
    required bool home,
    String? teamId,
  }) async {
    final i = matches.indexWhere((m) => m.id == matchId);
    final m = matches[i];
    matches[i] = _copy(
      m,
      homeId: home ? teamId : m.homeId,
      awayId: home ? m.awayId : teamId,
      setSides: true,
    );
  }

  @override
  Future<void> setStatus(String id, ChampionshipStatus status) async =>
      championship = championship.copyWith(status: status);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChampionshipTeam _entry(
  String id, {
  EntryStatus status = EntryStatus.accepted,
  String? teamId,
  String? ownerId,
}) => ChampionshipTeam(
  id: id,
  championshipId: 'c1',
  teamId: teamId,
  guestTeamId: teamId == null ? 'g-$id' : null,
  name: 'Time $id',
  status: status,
  ownerId: ownerId,
);

Championship _championship(ChampionshipFormat format) => Championship(
  id: 'c1',
  ownerId: 'u1',
  name: 'Copa do Bairro',
  modality: Modality.society,
  format: format,
);

Future<void> _pump(
  WidgetTester tester,
  FakeChampionshipRepository repository, {
  String userId = 'u1',
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        currentUserIdProvider.overrideWithValue(userId),
        championshipRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: ChampionshipPage(championshipId: 'c1', random: Random(7)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterScore(
  WidgetTester tester,
  String home,
  String away, {
  String? homePen,
  String? awayPen,
}) async {
  final fields = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(fields.at(0), home);
  await tester.enterText(fields.at(1), away);
  await tester.pumpAndSettle();
  if (homePen != null) {
    await tester.enterText(fields.at(2), homePen);
    await tester.enterText(fields.at(3), awayPen!);
  }
  await tester.tap(find.text('Salvar placar'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('pontos corridos: gera a tabela e mostra as rodadas', (
    tester,
  ) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league),
      [_entry('a'), _entry('b'), _entry('c'), _entry('d')],
    );
    await _pump(tester, repository);

    // Antes de começar abre em Times.
    expect(find.text('Time a'), findsOneWidget);
    await tester.tap(find.text('Gerar tabela'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar tabela').last);
    await tester.pumpAndSettle();

    expect(repository.championship.status, ChampionshipStatus.running);
    expect(repository.matches, hasLength(6));

    await tester.tap(find.text('Jogos'));
    await tester.pumpAndSettle();
    expect(find.text('Rodada 1'), findsOneWidget);
    expect(find.text('Data a definir'), findsWidgets);

    await tester.tap(find.text('Classificação'));
    await tester.pumpAndSettle();
    expect(find.text('Time a'), findsOneWidget);
    expect(find.text('SG'), findsOneWidget);
  });

  testWidgets('mata-mata: o empate vai aos pênaltis e o vencedor avança', (
    tester,
  ) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.knockout),
      [_entry('a'), _entry('b'), _entry('c'), _entry('d')],
    );
    await _pump(tester, repository);
    await tester.tap(find.text('Gerar tabela'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar tabela').last);
    await tester.pumpAndSettle();
    expect(repository.matches, hasLength(3));

    await tester.tap(find.text('Jogos'));
    await tester.pumpAndSettle();
    expect(find.text('Semifinal'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);

    // As duas semifinais: a primeira nos pênaltis.
    final semis = repository.matches.where((m) => m.round == 1).toList();
    for (final (index, semi) in semis.indexed) {
      await tester.tap(find.text(semi.homeId!.replaceFirst('', 'Time ')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lançar placar'));
      await tester.pumpAndSettle();
      if (index == 0) {
        await _enterScore(tester, '1', '1', homePen: '4', awayPen: '5');
      } else {
        await _enterScore(tester, '2', '0');
      }
    }
    final finalMatch = repository.matches.firstWhere((m) => m.round == 2);
    // Pênaltis: o visitante da primeira semifinal; e o mandante da segunda.
    expect(finalMatch.homeId, semis[0].awayId);
    expect(finalMatch.awayId, semis[1].homeId);

    await tester.tap(find.text('Time ${finalMatch.homeId}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lançar placar'));
    await tester.pumpAndSettle();
    await _enterScore(tester, '3', '1');
    expect(repository.championship.status, ChampionshipStatus.finished);

    await tester.tap(find.text('Chaveamento'));
    await tester.pumpAndSettle();
    expect(find.text('Campeão: Time ${finalMatch.homeId}'), findsOneWidget);
  });

  testWidgets('liga + mata-mata: os primeiros da liga vão ao mata-mata', (
    tester,
  ) async {
    final repository = FakeChampionshipRepository(
      const Championship(
        id: 'c1',
        ownerId: 'u1',
        name: 'Copa do Bairro',
        modality: Modality.society,
        format: ChampionshipFormat.leagueKnockout,
        knockoutQualifiers: 4,
      ),
      [
        for (final id in ['a', 'b', 'c', 'd', 'e']) _entry(id),
      ],
    );
    await _pump(tester, repository);
    await tester.tap(find.text('Gerar tabela'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Gerar tabela').last);
    await tester.pumpAndSettle();
    expect(repository.matches, hasLength(10));

    // Na liga, o time de letra menor sempre vence: a, b, c, d, e.
    for (final m in [...repository.matches]) {
      final homeWins = m.homeId!.compareTo(m.awayId!) < 0;
      await repository.setScore(
        m.id,
        home: homeWins ? 1 : 0,
        away: homeWins ? 0 : 1,
      );
    }
    // Abre de novo, com os placares.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, repository);
    expect(find.text('Liga (passam 4)'), findsOneWidget);

    await tester.tap(find.text('Jogos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar o mata-mata'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar mata-mata'));
    await tester.pumpAndSettle();

    final knockout = repository.matches
        .where((m) => m.stage == MatchStage.knockout)
        .toList();
    expect(knockout, hasLength(3));
    final semis = knockout.where((m) => m.round == 6).toList();
    expect(semis.map((m) => (m.homeId, m.awayId)), [('a', 'd'), ('b', 'c')]);
    expect(find.text('Gerar o mata-mata'), findsNothing);
    // Depois das rodadas da liga.
    await tester.scrollUntilVisible(
      find.text('Semifinal'),
      300,
      scrollable: find
          .ancestor(
            of: find.text('Rodada 1'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Semifinal'), findsOneWidget);
  });

  testWidgets('o dono do time convidado aceita', (tester) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league),
      [
        _entry('a'),
        _entry('x', status: EntryStatus.invited, teamId: 't-x', ownerId: 'u9'),
      ],
    );
    await _pump(tester, repository, userId: 'u9');
    // Quem não organiza não gera a tabela nem tira times.
    expect(find.text('Gerar tabela'), findsNothing);
    expect(find.byTooltip('Tirar Time a'), findsNothing);
    expect(find.text('Convidado'), findsOneWidget);

    await tester.tap(find.text('Aceitar'));
    await tester.pumpAndSettle();
    expect(repository.responses, [('x', true)]);
  });

  testWidgets('artilharia e garçons do campeonato', (tester) async {
    final repository =
        FakeChampionshipRepository(
            _championship(ChampionshipFormat.league)
                .copyWith(status: ChampionshipStatus.running),
            [_entry('a'), _entry('b'), _entry('c')],
          )
          ..stats = const ChampionshipStats(
            players: [
              StatsPlayer(
                name: 'Bruno',
                teamName: 'Time a',
                goals: 3,
                assists: 1,
                yellowCards: 2,
              ),
              StatsPlayer(name: 'Caio', teamName: 'Time b', goals: 1),
              StatsPlayer(
                name: 'Davi',
                teamName: 'Time c',
                assists: 2,
                redCards: 1,
              ),
            ],
            teams: [
              StatsTeam(
                name: 'Time a',
                played: 2,
                goalsFor: 5,
                goalsAgainst: 1,
                yellowCards: 2,
              ),
              StatsTeam(
                name: 'Time c',
                played: 2,
                goalsFor: 1,
                goalsAgainst: 4,
                redCards: 1,
              ),
            ],
            suspended: [
              SuspendedPlayer(
                name: 'Davi',
                teamName: 'Time c',
                reason: 'Expulso',
              ),
            ],
          );
    await _pump(tester, repository);
    await tester.ensureVisible(find.text('Estatísticas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estatísticas'));
    await tester.pumpAndSettle();

    // Artilharia: só quem fez gol, do maior para o menor.
    expect(find.text('3 gols'), findsOneWidget);
    expect(find.text('1 gol'), findsOneWidget);
    expect(find.text('Davi'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Bruno')).dy,
      lessThan(tester.getTopLeft(find.text('Caio')).dy),
    );

    await tester.ensureVisible(find.text('Assistências'));
    await tester.tap(find.text('Assistências'));
    await tester.pumpAndSettle();
    expect(find.text('2 assistências'), findsOneWidget);
    expect(find.text('1 assistência'), findsOneWidget);
    expect(find.text('Caio'), findsNothing);

    // Cartões: o suspenso em cima, com o motivo.
    await tester.ensureVisible(find.text('Cartões'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cartões'));
    await tester.pumpAndSettle();
    expect(find.text('Suspensos no próximo jogo'), findsOneWidget);
    expect(find.text('Expulso'), findsOneWidget);
    expect(
      find.text('3 amarelos = 1 jogo · vermelho = 1 jogo'),
      findsOneWidget,
    );

    // Fair play: menos pontos primeiro.
    await tester.ensureVisible(find.text('Fair play'));
    await tester.tap(find.text('Fair play'));
    await tester.pumpAndSettle();
    expect(find.text('2 pontos'), findsOneWidget);
    expect(find.text('3 pontos'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Time a')).dy,
      lessThan(tester.getTopLeft(find.text('Time c')).dy),
    );
  });

  testWidgets('organizador liga a inscrição por link e aceita um pedido', (
    tester,
  ) async {
    final texts = <String>[];
    final repository =
        FakeChampionshipRepository(_championship(ChampionshipFormat.league), [
            _entry('a'),
          ])
          ..requests = [
            ChampionshipRequest(
              id: 'r1',
              name: 'Várzea FC',
              createdAt: DateTime(2026, 11, 26),
              contactName: 'Zé',
              players: const ['10 · Tico', 'Teco'],
            ),
          ];
    await _pump(
      tester,
      repository,
      overrides: [
        shareTextProvider.overrideWithValue((text) async => texts.add(text)),
      ],
    );
    await tester.tap(find.text('Times (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Inscrição por link'), findsOneWidget);
    expect(find.text('1 pedido para responder'), findsOneWidget);
    expect(find.text('Sem conta · Zé · 2 atletas'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Inscrição por link'));
    await tester.pumpAndSettle();
    expect(repository.championship.signupEnabled, isTrue);
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    expect(texts.single, contains('/inscricao/abcd1234'));

    await tester.tap(find.byTooltip('Aceitar Várzea FC'));
    await tester.pumpAndSettle();
    expect(repository.answers.single, ('r1', true));
  });

  testWidgets('o organizador envia o símbolo do time fictício', (tester) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league),
      [_entry('a'), _entry('x', teamId: 't-x', ownerId: 'u1')],
    );
    await _pump(
      tester,
      repository,
      overrides: [
        pickImageProvider.overrideWithValue(
          (source, {maxSize = smallImageSize}) async => PickedImage(
            bytes: Uint8List.fromList([1, 2, 3]),
            contentType: 'image/png',
          ),
        ),
        cropSquareProvider.overrideWithValue((context, image) async => image),
      ],
    );
    // Só o fictício tem o selo da câmera.
    expect(find.bySemanticsLabel('Enviar símbolo do Time a'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('símbolo do Time x')), findsNothing);

    await tester.tap(find.text('Time a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher da galeria'));
    await tester.pumpAndSettle();
    expect(repository.guestLogos['g-a']?.contentType, 'image/png');
    expect(find.bySemanticsLabel('Trocar símbolo do Time a'), findsOneWidget);
  });

  testWidgets('menu do topo em bottom sheet: editar e excluir', (tester) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league),
      [_entry('a')],
    );
    await _pump(tester, repository);
    await tester.tap(find.byTooltip('Ações do campeonato'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Editar campeonato'), findsOneWidget);

    await tester.tap(find.text('Excluir campeonato'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isTrue);
  });

  testWidgets('em andamento, o menu só tem excluir', (tester) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league)
          .copyWith(status: ChampionshipStatus.running),
      [_entry('a')],
    );
    await _pump(tester, repository);
    await tester.tap(find.byTooltip('Ações do campeonato'));
    await tester.pumpAndSettle();
    expect(find.text('Editar campeonato'), findsNothing);
    expect(find.text('Excluir campeonato'), findsOneWidget);
  });

  testWidgets('compartilha a classificação e o campeão', (tester) async {
    final shared = <({Uint8List png, String text})>[];
    ChampionshipMatch played(String id, String h, String a, int hs, int as_) =>
        ChampionshipMatch(
          id: id,
          championshipId: 'c1',
          stage: MatchStage.league,
          round: 1,
          homeId: h,
          awayId: a,
          homeScore: hs,
          awayScore: as_,
        );
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league)
          .copyWith(status: ChampionshipStatus.finished),
      [_entry('a'), _entry('b'), _entry('c')],
    );
    repository.matches.addAll([
      played('m1', 'a', 'b', 2, 0),
      played('m2', 'b', 'c', 1, 1),
      played('m3', 'c', 'a', 0, 3),
    ]);
    await _pump(
      tester,
      repository,
      overrides: [
        shareImageProvider.overrideWithValue(
          (png, text) async => shared.add((png: png, text: text)),
        ),
      ],
    );

    await tester.tap(find.byTooltip('Compartilhar campeonato'));
    await tester.pumpAndSettle();
    final card = find.byType(ChampionshipShareCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('CAMPEÃO')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Time a')),
      findsNWidgets(2), // no destaque e na classificação
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Compartilhar imagem'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(shared.single.png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(shared.single.text, 'Time a é campeão do Copa do Bairro!');
  });

  testWidgets('antes da tabela, só o organizador vê o compartilhar', (
    tester,
  ) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league),
      [_entry('a')],
    );
    await _pump(tester, repository, userId: 'u2');
    expect(find.byTooltip('Compartilhar campeonato'), findsNothing);
  });

  testWidgets('organizador liga o link público e compartilha', (tester) async {
    final texts = <String>[];
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league),
      [_entry('a')],
    );
    await _pump(
      tester,
      repository,
      overrides: [
        shareTextProvider.overrideWithValue((text) async => texts.add(text)),
      ],
    );

    await tester.tap(find.byTooltip('Compartilhar campeonato'));
    await tester.pumpAndSettle();
    // Antes da tabela não há imagem; o link começa desligado.
    expect(find.text('Compartilhar imagem'), findsNothing);
    expect(find.text('Compartilhar link'), findsNothing);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(repository.championship.publicEnabled, isTrue);
    final url = publicChampionshipUrl(repository.championship.publicSlug!);
    expect(find.text(url), findsOneWidget);

    await tester.tap(find.text('Compartilhar link'));
    await tester.pumpAndSettle();
    expect(texts.single, 'Acompanhe o Copa do Bairro no SportLeague: $url');

    // Trocar o link gera outro código.
    await tester.tap(find.text('Trocar link'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Trocar'));
    await tester.pumpAndSettle();
    expect(
      find.text(publicChampionshipUrl(repository.championship.publicSlug!)),
      findsOneWidget,
    );
    expect(find.text(url), findsNothing);
  });

  testWidgets('com o link ligado, quem acompanha também compartilha', (
    tester,
  ) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.league)
          .copyWith(publicEnabled: true, publicSlug: 'abc123'),
      [_entry('a')],
    );
    await _pump(tester, repository, userId: 'u2');
    await tester.tap(find.byTooltip('Compartilhar campeonato'));
    await tester.pumpAndSettle();
    expect(find.text(publicChampionshipUrl('abc123')), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Trocar link'), findsNothing);
  });

  testWidgets('sem times suficientes não gera', (tester) async {
    final repository = FakeChampionshipRepository(
      _championship(ChampionshipFormat.knockout),
      [_entry('a'), _entry('b'), _entry('c')],
    );
    await _pump(tester, repository);
    await tester.tap(find.text('Gerar tabela'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4, 8, 16 ou 32'), findsOneWidget);
    expect(repository.matches, isEmpty);
  });

  testWidgets('grupos: mostra o sorteio, sorteia de novo e gera os jogos', (
    tester,
  ) async {
    final repository = FakeChampionshipRepository(
      const Championship(
        id: 'c1',
        ownerId: 'u1',
        name: 'Copa do Bairro',
        modality: Modality.society,
        format: ChampionshipFormat.groups,
        groupCount: 2,
        qualifiersPerGroup: 1,
        teamCount: 6,
        groupSize: 3,
      ),
      [for (final id in 'abcdef'.split('')) _entry(id)],
    );
    await _pump(tester, repository);
    expect(find.textContaining('6 de 6 confirmados'), findsOneWidget);

    await tester.tap(find.text('Sortear grupos'));
    await tester.pumpAndSettle();
    expect(find.text('Sorteio dos grupos'), findsOneWidget);
    expect(find.text('Grupo A'), findsOneWidget);
    expect(find.text('Grupo B'), findsOneWidget);

    await tester.tap(find.text('Sortear de novo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e gerar jogos'));
    await tester.pumpAndSettle();

    expect(repository.championship.status, ChampionshipStatus.running);
    // 2 grupos de 3: 3 jogos em cada.
    expect(repository.matches, hasLength(6));
    final labels = [for (final t in repository.teams) t.groupLabel];
    expect(labels.where((l) => l == 'A'), hasLength(3));
    expect(labels.where((l) => l == 'B'), hasLength(3));
  });
}
