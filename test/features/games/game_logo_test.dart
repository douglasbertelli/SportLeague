import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/games/domain/game.dart';

Map<String, dynamic> _row({
  Map<String, dynamic>? opponentTeam,
  Map<String, dynamic>? opponentGuest,
  Map<String, dynamic>? championshipMatch,
}) => {
  'id': 'g1',
  'team_id': 'team-a',
  'opponent': 'Fictício FC',
  'scheduled_at': '2026-11-10T18:00:00Z',
  'status': 'scheduled',
  'opponent_team': ?opponentTeam,
  'opponent_guest': ?opponentGuest,
  'championship_match': ?championshipMatch,
};

void main() {
  test('jogo de campeonato contra fictício: o símbolo vem da inscrição', () {
    final game = Game.fromMap(
      _row(
        championshipMatch: {
          'round': 2,
          'stage': 'league',
          'group_label': null,
          'championship': {'id': 'c1', 'name': 'Copa'},
          'home': {'logo_url': null, 'guest_team_id': null},
          'away': {'logo_url': 'https://logo/fict.png', 'guest_team_id': 'g9'},
        },
      ),
    );
    expect(game.opponentLogoFor('team-a'), 'https://logo/fict.png');
    expect(game.championship?.guestLogoUrl, 'https://logo/fict.png');
  });

  test('amistoso contra o fictício do dono: o símbolo dele', () {
    final game = Game.fromMap(
      _row(opponentGuest: {'logo_url': 'https://logo/meu-fict.png'}),
    );
    expect(game.opponentLogoFor('team-a'), 'https://logo/meu-fict.png');
  });

  test('time da plataforma: o logo dele vem primeiro', () {
    final game = Game.fromMap(
      _row(
        opponentTeam: {'logo_url': 'https://logo/time.png', 'city': 'Campinas'},
      ),
    );
    expect(game.opponentLogoFor('team-a'), 'https://logo/time.png');
  });

  test('fictício sem símbolo (ou de outro dono): sem logo', () {
    expect(Game.fromMap(_row()).opponentLogoFor('team-a'), isNull);
  });
}
