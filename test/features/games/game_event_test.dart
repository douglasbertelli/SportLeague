import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/domain/game_event.dart';
import 'package:sport_league/features/games/domain/match_clock.dart';
import 'package:sport_league/features/games/presentation/live_events.dart';
import 'package:sport_league/features/teams/domain/team.dart';

void main() {
  group('minuto do lance', () {
    test('1º tempo conta do início', () {
      expect(formatEventMinute(MatchPhase.first, 0, 25), "1'");
      expect(formatEventMinute(MatchPhase.first, 22 * 60 + 10, 25), "23'");
    });

    test('2º tempo soma a duração do 1º', () {
      expect(formatEventMinute(MatchPhase.second, 5 * 60, 25), "31'");
    });

    test('acréscimo vira 45+2', () {
      expect(formatEventMinute(MatchPhase.first, 46 * 60, 45), "45+2'");
      expect(formatEventMinute(MatchPhase.second, 45 * 60, 45), "90+1'");
    });

    test('sem relógio, sem minuto', () {
      expect(formatEventMinute(null, null, 25), '');
    });
  });

  group('quem lança', () {
    final vsPlatform = Game(
      id: 'g1',
      teamId: 'host',
      opponent: 'Rival',
      opponentTeamId: 'rival',
      scheduledAt: DateTime(2026, 11, 24, 15),
    );
    final vsGuest = Game(
      id: 'g2',
      teamId: 'host',
      opponent: 'Convidado',
      opponentGuestId: 'guest',
      scheduledAt: DateTime(2026, 11, 24, 15),
    );

    test('quem marcou lança os gols dos dois lados e o seu lado todo', () {
      for (final kind in GameEventKind.values) {
        expect(
          canAddGameEvent(vsPlatform, 'host', side: GameSide.host, kind: kind),
          isTrue,
        );
      }
      expect(
        canAddGameEvent(
          vsPlatform,
          'host',
          side: GameSide.opponent,
          kind: GameEventKind.goal,
        ),
        isTrue,
      );
      expect(
        canAddGameEvent(
          vsPlatform,
          'host',
          side: GameSide.opponent,
          kind: GameEventKind.yellowCard,
        ),
        isFalse,
        reason: 'o cartão do adversário da plataforma é dele',
      );
    });

    test('no vôlei, ninguém lança lances (o placar é por sets)', () {
      final volleyball = Game(
        id: 'g3',
        teamId: 'host',
        opponent: 'Convidado',
        opponentGuestId: 'guest',
        modality: Modality.volleyballIndoor,
        scheduledAt: DateTime(2026, 11, 24, 15),
      );
      for (final side in GameSide.values) {
        for (final kind in GameEventKind.values) {
          expect(
            canAddGameEvent(volleyball, 'host', side: side, kind: kind),
            isFalse,
            reason: '$kind',
          );
        }
      }
    });

    test('contra convidado, quem marcou lança tudo', () {
      expect(
        canAddGameEvent(
          vsGuest,
          'host',
          side: GameSide.opponent,
          kind: GameEventKind.redCard,
        ),
        isTrue,
      );
    });

    test('o adversário lança os lances dele, menos gols', () {
      expect(
        canAddGameEvent(
          vsPlatform,
          'rival',
          side: GameSide.opponent,
          kind: GameEventKind.substitution,
        ),
        isTrue,
      );
      expect(
        canAddGameEvent(
          vsPlatform,
          'rival',
          side: GameSide.opponent,
          kind: GameEventKind.goal,
        ),
        isFalse,
      );
      expect(
        canAddGameEvent(
          vsPlatform,
          'rival',
          side: GameSide.host,
          kind: GameEventKind.yellowCard,
        ),
        isFalse,
      );
    });
  });

  test('sigla do time no placar', () {
    expect(teamAbbreviation('Unidos FC'), 'UNI');
    expect(teamAbbreviation('Juventude Oeste'), 'JUV');
    expect(teamAbbreviation('Grêmio Pinheiros'), 'GRE');
    expect(teamAbbreviation('EC São Paulo'), 'SAO');
    expect(teamAbbreviation('A B C'), 'ABC');
    expect(teamAbbreviation('  '), '?');
  });

  test('gol contra vale para o outro lado', () {
    final event = GameEvent(
      id: 'e1',
      gameId: 'g1',
      side: GameSide.host,
      kind: GameEventKind.ownGoal,
      createdAt: DateTime(2026),
    );
    expect(event.scoringSide, GameSide.opponent);
  });

  test('lê o lance do banco com o apelido do atleta', () {
    final event = GameEvent.fromMap({
      'id': 'e1',
      'game_id': 'g1',
      'side': 'opponent',
      'kind': 'second_yellow',
      'created_at': '2026-11-24T18:00:00Z',
      'athlete_id': 'a1',
      'athlete': {
        'name': 'José',
        'profile': {'nickname': 'Zé'},
      },
      'related_athlete_id': null,
      'related': null,
      'penalty': false,
      'phase': 'second',
      'clock_seconds': 600,
    });
    expect(event.kind, GameEventKind.secondYellow);
    expect(event.side, GameSide.opponent);
    expect(event.title, 'Segundo amarelo · Zé');
    expect(event.minuteLabel(25), "36'");
    // Com cronômetro, o tempo dele; sem cronômetro, a hora do celular.
    expect(event.timeLabel, '10:00');
    final noClock = GameEvent(
      id: 'e2',
      gameId: 'g1',
      side: GameSide.host,
      kind: GameEventKind.goal,
      createdAt: DateTime(2026, 11, 24, 17, 5),
    );
    expect(noClock.timeLabel, '17:05');
  });
}
