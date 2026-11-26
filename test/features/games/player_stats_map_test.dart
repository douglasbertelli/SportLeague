import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/games/domain/player_stats.dart';

/// Súmula genérica (Etapa 4): a linha lê `stats` e, sem ela, as colunas do
/// futebol; grava só `stats`.
void main() {
  const base = {'game_id': 'g', 'team_id': 't', 'athlete_id': 'a'};

  test('lê stats quando o banco já tem a coluna', () {
    final row = PlayerGameStats.fromMap({
      ...base,
      // As colunas ficam iguais a stats no banco; aqui diferentes de
      // propósito, para ver que stats vale.
      'goals': 0,
      'red_card': false,
      'stats': {'goals': 2, 'assists': 1, 'yellow_cards': 1, 'red_card': 1},
      'best_player': true,
    });
    expect(
      (row.goals, row.assists, row.yellowCards, row.redCard, row.bestPlayer),
      (2, 1, 1, true, true),
    );
  });

  test('sem stats, lê as colunas (banco antes da migration)', () {
    final row = PlayerGameStats.fromMap({
      ...base,
      'goals': 3,
      'assists': 2,
      'yellow_cards': 2,
      'red_card': true,
    });
    expect(
      (row.goals, row.assists, row.yellowCards, row.redCard),
      (3, 2, 2, true),
    );
  });

  test('chave ausente em stats cai na coluna; sem as duas, zero', () {
    final row = PlayerGameStats.fromMap({
      ...base,
      'assists': 4,
      'stats': {'goals': 1},
    });
    expect(
      (row.goals, row.assists, row.yellowCards, row.redCard),
      (1, 4, 0, false),
    );
  });

  test('grava só stats, com a flag em 0 ou 1', () {
    const row = PlayerGameStats(
      gameId: 'g',
      teamId: 't',
      athleteId: 'a',
      goals: 2,
      assists: 1,
      redCard: true,
      bestPlayer: true,
    );
    expect(row.toMap(), {
      'game_id': 'g',
      'team_id': 't',
      'athlete_id': 'a',
      'stats': {'goals': 2, 'assists': 1, 'yellow_cards': 0, 'red_card': 1},
      'best_player': true,
    });
    expect(PlayerGameStats.fromMap(row.toMap()).redCard, isTrue);
  });
}
