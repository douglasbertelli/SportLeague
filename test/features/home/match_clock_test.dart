import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/media/whistle_player.dart';
import 'package:sport_league/core/theme/app_theme.dart';
import 'package:sport_league/features/games/data/game_repository.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/domain/match_clock.dart';
import 'package:sport_league/features/home/presentation/match_clock_panel.dart';
import 'package:sport_league/features/teams/data/team_repository.dart';
import 'package:sport_league/features/teams/domain/team.dart';

import '../teams/fakes.dart';

final _kickoff = DateTime(2026, 10, 31, 15);

Game _game([MatchClock? clock]) => Game(
  id: 'g1',
  teamId: 'team-a',
  opponent: 'Real Bairro',
  opponentTeamId: 'team-rival',
  modality: Modality.society,
  scheduledAt: _kickoff,
  clock: clock,
);

/// Apitos tocados no teste atual.
final _whistles = <Whistle>[];

Future<FakeGameRepository> _pump(
  WidgetTester tester,
  Game game, {
  String viewer = 'team-a',
  required DateTime Function() now,
}) async {
  final games = FakeGameRepository({
    'team-a': [game],
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameRepositoryProvider.overrideWithValue(games),
        // O dono do time ativo (o técnico não controla o relógio).
        canManageTeamProvider.overrideWithValue(true),
        playWhistleProvider.overrideWithValue((whistle) async {
          _whistles.add(whistle);
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: MatchClockPanel(game: game, viewerTeamId: viewer, clock: now),
        ),
      ),
    ),
  );
  return games;
}

void main() {
  group('MatchClock', () {
    test('sem fase no banco, sem relógio', () {
      expect(MatchClock.fromMap({'match_phase': null}), isNull);
      final clock = MatchClock.fromMap({
        'match_phase': 'second',
        'clock_started_at': null,
        'clock_elapsed': 754,
        'period_minutes': 25,
      })!;
      expect(clock.phase, MatchPhase.second);
      expect(clock.running, isFalse);
      expect(formatClock(clock.elapsedAt(DateTime.now())), '12:34');
    });

    test('correndo soma o tempo desde o último início', () {
      final clock = MatchClock(
        phase: MatchPhase.first,
        startedAt: _kickoff,
        elapsed: const Duration(minutes: 10),
        periodMinutes: 20,
      );
      final now = _kickoff.add(const Duration(minutes: 9, seconds: 59));
      expect(formatClock(clock.elapsedAt(now)), '19:59');
      expect(clock.overtimeAt(now), isFalse);
      expect(clock.overtimeAt(now.add(const Duration(seconds: 1))), isTrue);
    });

    test('duração sugerida pela modalidade', () {
      expect(MatchClock.defaultPeriodMinutes(Modality.futsal), 20);
      expect(MatchClock.defaultPeriodMinutes(Modality.field), 45);
    });

    test('relógio rodando mantém o jogo em andamento depois de 2 horas', () {
      final late = _kickoff.add(const Duration(hours: 3));
      expect(_game().isLiveAt(late), isFalse);
      expect(
        _game(const MatchClock(phase: MatchPhase.second)).isLiveAt(late),
        isTrue,
      );
      expect(
        _game(const MatchClock(phase: MatchPhase.finished)).isLiveAt(late),
        isFalse,
      );
    });
  });

  group('painel do relógio', () {
    setUp(_whistles.clear);
    testWidgets('quem marcou inicia com a duração de cada tempo', (
      tester,
    ) async {
      final games = await _pump(tester, _game(), now: () => _kickoff);
      await tester.tap(find.text('Iniciar 1º tempo'));
      await tester.pumpAndSettle();
      // Society: 25 minutos sugeridos; ajusta para 24.
      expect(find.text('25 min'), findsOneWidget);
      await tester.tap(find.byTooltip('Menos 1 minuto'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Iniciar 1º tempo').last,
      );
      await tester.pumpAndSettle();
      expect(games.clockActions, [('g1', ClockAction.start, 24)]);
      expect(_whistles, [Whistle.start]);
    });

    testWidgets('cronômetro corre, pausa e avisa no fim do tempo', (
      tester,
    ) async {
      var now = _kickoff.add(const Duration(minutes: 19, seconds: 58));
      final games = await _pump(
        tester,
        _game(
          MatchClock(
            phase: MatchPhase.first,
            startedAt: _kickoff,
            periodMinutes: 20,
          ),
        ),
        now: () => now,
      );
      expect(find.text('19:58'), findsOneWidget);
      expect(find.text('1º tempo · 20 min'), findsOneWidget);
      expect(find.text('Acréscimo'), findsNothing);

      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('20:01'), findsOneWidget);
      expect(find.text('Acréscimo'), findsOneWidget);
      expect(find.textContaining('Acabou o tempo do 1º tempo'), findsOneWidget);

      await tester.tap(find.text('Pausar'));
      await tester.pump();
      expect(games.clockActions.last, ('g1', ClockAction.pause, null));

      await tester.tap(find.text('Encerrar 1º tempo'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Encerrar 1º tempo').last,
      );
      await tester.pumpAndSettle();
      expect(games.clockActions.last, ('g1', ClockAction.endHalf, null));
      // Pausar não apita; encerrar o 1º tempo apita curto e longo.
      expect(_whistles, [Whistle.halfTime]);
    });

    testWidgets('intervalo: só iniciar o 2º tempo', (tester) async {
      final games = await _pump(
        tester,
        _game(const MatchClock(phase: MatchPhase.interval, periodMinutes: 20)),
        now: () => _kickoff,
      );
      expect(find.text('Intervalo'), findsOneWidget);
      expect(find.text('Pausar'), findsNothing);
      await tester.tap(find.text('Iniciar 2º tempo'));
      await tester.pump();
      expect(games.clockActions.last, ('g1', ClockAction.startSecond, null));
      expect(_whistles, [Whistle.start]);
    });

    testWidgets('o adversário ouve o apito quando o tempo muda', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          gameRepositoryProvider.overrideWithValue(FakeGameRepository({})),
          canManageTeamProvider.overrideWithValue(true),
          playWhistleProvider.overrideWithValue((whistle) async {
            _whistles.add(whistle);
          }),
        ],
      );
      addTearDown(container.dispose);
      Future<void> show(MatchPhase phase) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: MatchClockPanel(
                game: _game(MatchClock(phase: phase, periodMinutes: 20)),
                viewerTeamId: 'team-rival',
                clock: () => _kickoff,
              ),
            ),
          ),
        ),
      );

      // Ao abrir, já no intervalo: sem apito.
      await show(MatchPhase.interval);
      expect(_whistles, isEmpty);
      await show(MatchPhase.second);
      await show(MatchPhase.finished);
      expect(_whistles, [Whistle.start, Whistle.fullTime]);
    });

    testWidgets('o adversário só acompanha', (tester) async {
      await _pump(tester, _game(), viewer: 'team-rival', now: () => _kickoff);
      expect(find.text('Aguardando o início da partida'), findsOneWidget);
      expect(find.text('Iniciar 1º tempo'), findsNothing);

      await _pump(
        tester,
        _game(
          MatchClock(
            phase: MatchPhase.second,
            startedAt: _kickoff,
            periodMinutes: 20,
          ),
        ),
        viewer: 'team-rival',
        now: () => _kickoff.add(const Duration(minutes: 5)),
      );
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('Pausar'), findsNothing);
      expect(find.text('Encerrar jogo'), findsNothing);
      expect(find.byTooltip('Mais opções do relógio'), findsNothing);
    });
  });
}
